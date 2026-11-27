import SwiftUI
import Observation

@Observable
final class TransferJob: Identifiable {
    let id = UUID()
    let title: String
    let control = TransferControl()
    var fraction: Double = 0
    var currentName = ""
    var isFinished = false
    /// One entry per item of a copy or move (empty for other kinds of jobs).
    var files: [TransferFile] = []
    var doneBytes: Int64 = 0
    var totalBytes: Int64 = 0
    /// Smoothed bytes per second.
    var speed: Double = 0
    var move = false
    @ObservationIgnored var conflict: ConflictChoice?
    @ObservationIgnored var items: [(src: URL, dstDir: URL)] = []

    init(title: String) { self.title = title }

    var failedFiles: [TransferFile] { files.filter { $0.state == .failed } }
}

final class ConflictRequest: Identifiable {
    let id = UUID()
    let info: ConflictInfo
    let continuation: CheckedContinuation<ConflictAnswer, Never>
    init(info: ConflictInfo, continuation: CheckedContinuation<ConflictAnswer, Never>) {
        self.info = info
        self.continuation = continuation
    }
}

@Observable
final class TransferManager {
    var jobs: [TransferJob] = []
    private var queue: [ConflictRequest] = []

    var onFinished: (() -> Void)?
    var onError: ((String) -> Void)?
    var onCompleted: ((_ move: Bool, _ records: [TransferRecord], _ batch: UUID?) -> Void)?

    var pending: ConflictRequest? { queue.first }
    var hasActive: Bool { jobs.contains { !$0.isFinished } }
    /// A finished transfer that left failed items stays in the list until it is retried or dismissed.
    var hasFailed: Bool { jobs.contains { $0.isFinished && !$0.failedFiles.isEmpty } }
    var showsIndicator: Bool { hasActive || hasFailed }
    var overall: Double {
        let active = jobs.filter { !$0.isFinished }
        guard !active.isEmpty else { return 0 }
        return active.map(\.fraction).reduce(0, +) / Double(active.count)
    }

    func start(items: [(src: URL, dstDir: URL)], move: Bool, conflict: ConflictChoice? = nil, batch: UUID? = nil) {
        guard !items.isEmpty else { return }
        let verb = move ? "Moving" : "Copying"
        let what = items.count == 1 ? items[0].src.lastPathComponent : "\(items.count) items"
        let folders = Set(items.map { $0.dstDir.standardizedFileURL.path })
        let title = folders.count == 1 ? "\(verb) \(what) to \(items[0].dstDir.lastPathComponent)" : "\(verb) \(what)"
        let job = TransferJob(title: title)
        job.move = move
        job.conflict = conflict
        job.items = items
        jobs.append(job)

        let engine = TransferEngine(move: move, control: job.control, preset: conflict) { [weak self] info in
            await self?.askUser(info) ?? ConflictAnswer(choice: .stop, applyToAll: false)
        }
        let pairs = items

        Task { [weak self] in
            // Poll shared progress while the engine works in the background.
            let poller = Task { @MainActor in
                var lastDone: Int64 = 0
                var lastTime = Date()
                while !Task.isCancelled {
                    let s = job.control.snapshot
                    job.fraction = min(Double(s.done) / Double(s.total), 1)
                    job.currentName = s.name
                    job.doneBytes = s.done
                    job.totalBytes = s.total
                    if job.files != s.files { job.files = s.files }
                    let now = Date()
                    let dt = now.timeIntervalSince(lastTime)
                    if dt >= 0.5 {
                        let instant = Double(s.done - lastDone) / dt
                        job.speed = job.speed == 0 ? instant : job.speed * 0.7 + instant * 0.3
                        lastDone = s.done
                        lastTime = now
                    }
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
            let failures = await Task.detached(priority: .userInitiated) {
                await engine.run(items: pairs)
            }.value
            poller.cancel()
            let last = job.control.snapshot
            job.files = last.files
            job.doneBytes = last.done
            job.totalBytes = last.total
            job.speed = 0
            job.fraction = 1
            job.isFinished = true
            self?.onFinished?()
            if !engine.records.isEmpty || batch != nil { self?.onCompleted?(move, engine.records, batch) }
            if !failures.isEmpty {
                self?.onError?(failures.joined(separator: "\n"))
            }
            // A transfer with failed items stays in the list so it can be retried.
            if job.failedFiles.isEmpty {
                try? await Task.sleep(for: .seconds(1))
                self?.jobs.removeAll { $0.id == job.id }
            }
        }
    }

    func cancel(_ job: TransferJob) {
        job.control.cancelled = true
    }

    func dismiss(_ job: TransferJob) {
        jobs.removeAll { $0.id == job.id }
    }

    /// Starts a new transfer with only the items that failed.
    func retry(_ job: TransferJob) {
        let failed = Set(job.failedFiles.map(\.id))
        let again = job.items.enumerated().filter { failed.contains($0.offset) }.map(\.element)
        jobs.removeAll { $0.id == job.id }
        start(items: again, move: job.move, conflict: job.conflict)
    }

    private func askUser(_ info: ConflictInfo) async -> ConflictAnswer {
        await withCheckedContinuation { cont in
            queue.append(ConflictRequest(info: info, continuation: cont))
        }
    }

    func answer(_ choice: ConflictChoice, applyToAll: Bool) {
        guard !queue.isEmpty else { return }
        let req = queue.removeFirst()
        req.continuation.resume(returning: ConflictAnswer(choice: choice, applyToAll: applyToAll))
    }
}

// MARK: - Views

struct ConflictSheet: View {
    let request: ConflictRequest
    let manager: TransferManager
    @State private var applyToAll = false

    private func describe(isDir: Bool, size: Int64, date: Date?) -> String {
        let s = isDir ? "Folder" : ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        let d = date?.formatted(date: .abbreviated, time: .shortened) ?? ""
        return d.isEmpty ? s : "\(s), \(d)"
    }

    var body: some View {
        let i = request.info
        VStack(alignment: .leading, spacing: 12) {
            Text("\"\(i.name)\" already exists in this location.")
                .font(.headline)
            VStack(alignment: .leading, spacing: 4) {
                Text("Existing: " + describe(isDir: i.dstIsDir, size: i.dstSize, date: i.dstDate))
                Text("New: " + describe(isDir: i.srcIsDir, size: i.srcSize, date: i.srcDate))
            }
            .foregroundStyle(.secondary)

            Toggle("Apply to all", isOn: $applyToAll)

            HStack {
                Button("Stop") { manager.answer(.stop, applyToAll: false) }
                Spacer()
                Button("Skip") { manager.answer(.skip, applyToAll: applyToAll) }
                Button("Keep Both") { manager.answer(.keepBoth, applyToAll: applyToAll) }
                if i.srcIsDir && i.dstIsDir {
                    Button("Merge") { manager.answer(.merge, applyToAll: applyToAll) }
                }
                Button("Replace") { manager.answer(.replace, applyToAll: applyToAll) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
        .interactiveDismissDisabled()
    }
}

/// The transfer list as a card in the top right corner of the window (under the toolbar indicator).
struct TransfersOverlay: View {
    let app: AppModel

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.001)
                .onTapGesture { app.showTransfers = false }
            TransferList(manager: app.transfers)
            .fixedSize(horizontal: false, vertical: true)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .windowBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.15), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.18), radius: 14, y: 5)
            .padding(.top, 66)
            .padding(.trailing, 14)
        }
    }
}

struct TransferList: View {
    let manager: TransferManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Transfers").font(.callout.weight(.medium))
                Spacer(minLength: 8)
                Text(summary).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            ForEach(manager.jobs.prefix(5)) { job in
                Divider()
                TransferJobView(job: job, manager: manager)
            }
            if manager.jobs.count > 5 {
                Divider()
                Text("\(manager.jobs.count - 5) more transfers")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(12)
            }
        }
        .frame(width: 380)
    }

    private var summary: String {
        let active = manager.jobs.filter { !$0.isFinished }.count
        let failed = manager.jobs.filter { $0.isFinished && !$0.failedFiles.isEmpty }.count
        var parts: [String] = []
        if active > 0 { parts.append("\(active) active") }
        if failed > 0 { parts.append("\(failed) failed") }
        return parts.joined(separator: ", ")
    }
}

private func formatBytes(_ n: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
}

private struct ThinBar: View {
    let value: Double
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height / 2).fill(Color.primary.opacity(0.1))
                RoundedRectangle(cornerRadius: height / 2).fill(Color.filetor)
                    .frame(width: g.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: height)
    }
}

private struct TransferJobView: View {
    let job: TransferJob
    let manager: TransferManager

    private var failed: Int { job.failedFiles.count }
    private var doneCount: Int { job.files.filter { $0.state == .done }.count }

    /// Failed, running, the last two finished and the next three waiting items, in their own order.
    private var visibleFiles: [TransferFile] {
        let waiting = job.files.filter { $0.state == .waiting }
        let finished = job.files.filter { $0.state == .done }
        var ids = Set(job.files.filter { $0.state == .failed || $0.state == .active || $0.state == .cancelled }.map(\.id))
        ids.formUnion(finished.suffix(2).map(\.id))
        ids.formUnion(waiting.prefix(3).map(\.id))
        return job.files.filter { ids.contains($0.id) }
    }

    private var hiddenWaiting: Int {
        max(job.files.filter { $0.state == .waiting }.count - 3, 0)
    }

    private var timeLeft: String {
        guard job.speed > 1, job.totalBytes > job.doneBytes else { return "" }
        let seconds = Double(job.totalBytes - job.doneBytes) / job.speed
        if seconds < 60 { return "less than a minute left" }
        let minutes = Int((seconds / 60).rounded())
        if minutes < 60 { return "\(minutes) min left" }
        return "\(minutes / 60) h \(minutes % 60) min left"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(job.title)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                if job.isFinished {
                    if failed > 0 {
                        Button("Retry") { manager.retry(job) }
                            .buttonStyle(.link)
                            .font(.caption)
                        Button { manager.dismiss(job) } label: { Image(systemName: "xmark") }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                            .help("Dismiss")
                    }
                } else {
                    Button { manager.cancel(job) } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .help("Cancel")
                }
            }
            if !job.isFinished {
                ThinBar(value: job.fraction)
                    .padding(.vertical, 2)
            }
            if !job.files.isEmpty {
                HStack(spacing: 8) {
                    if job.isFinished {
                        if failed > 0 {
                            Text("\(failed) of \(job.files.count) failed").foregroundStyle(.red)
                        } else {
                            Text("Finished").foregroundStyle(.secondary)
                        }
                    } else {
                        Text("\(doneCount) of \(job.files.count) files, \(formatBytes(job.doneBytes)) of \(formatBytes(job.totalBytes))")
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if !job.isFinished && job.speed > 1 {
                        Text([formatBytes(Int64(job.speed)) + "/s", timeLeft].filter { !$0.isEmpty }.joined(separator: ", "))
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(visibleFiles) { file in
                        TransferFileRow(file: file, move: job.move)
                    }
                    if hiddenWaiting > 0 {
                        Text("\(hiddenWaiting) more waiting")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 26)
                            .padding(.vertical, 3)
                    }
                }
                .padding(.top, 4)
            } else if !job.isFinished {
                Text(job.currentName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(12)
    }
}

private struct TransferFileRow: View {
    let file: TransferFile
    let move: Bool

    private var trailing: String {
        switch file.state {
        case .active:
            return file.size > 0 ? "\(Int(Double(file.done) / Double(file.size) * 100))%" : ""
        case .failed:
            return move ? "Not moved" : "Not copied"
        case .cancelled:
            return "Cancelled"
        case .waiting, .done:
            return formatBytes(file.size)
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch file.state {
        case .done:
            Image(systemName: "checkmark").font(.caption).foregroundStyle(.secondary)
        case .active:
            ProgressView().controlSize(.mini)
        case .waiting:
            Circle().stroke(Color.primary.opacity(0.3), lineWidth: 1).frame(width: 11, height: 11)
        case .failed:
            Image(systemName: "exclamationmark.circle").foregroundStyle(.red)
        case .cancelled:
            Image(systemName: "minus.circle").foregroundStyle(.secondary)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            icon.frame(width: 18, height: 16)
            VStack(alignment: .leading, spacing: 3) {
                Text(file.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(file.state == .waiting || file.state == .cancelled ? Color.secondary : Color.primary)
                if file.state == .active {
                    ThinBar(value: Double(file.done) / Double(max(file.size, 1)), height: 3)
                }
                if file.state == .failed, let message = file.message {
                    Text(message).font(.caption).foregroundStyle(.red)
                }
            }
            Spacer(minLength: 8)
            Text(trailing)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .font(.callout)
        .padding(.vertical, 3)
    }
}
