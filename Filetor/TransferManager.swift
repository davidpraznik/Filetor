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

    init(title: String) { self.title = title }
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
    var onCompleted: ((_ move: Bool, _ records: [TransferRecord]) -> Void)?

    var pending: ConflictRequest? { queue.first }
    var hasActive: Bool { jobs.contains { !$0.isFinished } }
    var overall: Double {
        let active = jobs.filter { !$0.isFinished }
        guard !active.isEmpty else { return 0 }
        return active.map(\.fraction).reduce(0, +) / Double(active.count)
    }

    func start(items: [(src: URL, dstDir: URL)], move: Bool, conflict: ConflictChoice? = nil) {
        guard !items.isEmpty else { return }
        let verb = move ? "Moving" : "Copying"
        let title = items.count == 1 ? "\(verb) \(items[0].src.lastPathComponent)" : "\(verb) \(items.count) items"
        let job = TransferJob(title: title)
        jobs.append(job)

        let engine = TransferEngine(move: move, control: job.control, preset: conflict) { [weak self] info in
            await self?.askUser(info) ?? ConflictAnswer(choice: .stop, applyToAll: false)
        }
        let pairs = items

        Task { [weak self] in
            // Poll shared progress while the engine works in the background.
            let poller = Task { @MainActor in
                while !Task.isCancelled {
                    let s = job.control.snapshot
                    job.fraction = min(Double(s.done) / Double(s.total), 1)
                    job.currentName = s.name
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
            let failures = await Task.detached(priority: .userInitiated) {
                await engine.run(items: pairs)
            }.value
            poller.cancel()
            job.fraction = 1
            job.isFinished = true
            self?.onFinished?()
            if !engine.records.isEmpty { self?.onCompleted?(move, engine.records) }
            if !failures.isEmpty {
                self?.onError?(failures.joined(separator: "\n"))
            }
            try? await Task.sleep(for: .seconds(1))
            self?.jobs.removeAll { $0.id == job.id }
        }
    }

    func cancel(_ job: TransferJob) {
        job.control.cancelled = true
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

struct TransferList: View {
    let manager: TransferManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(manager.jobs) { job in
                VStack(alignment: .leading, spacing: 4) {
                    Text(job.title).font(.callout)
                    HStack {
                        ProgressView(value: job.fraction)
                        Button { manager.cancel(job) } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .help("Cancel")
                    }
                    Text(job.currentName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .padding(14)
        .frame(width: 300)
    }
}
