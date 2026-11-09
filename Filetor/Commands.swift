import SwiftUI
import AppKit
import CryptoKit

// MARK: - Report model (Find Duplicates, Compare Folders)

nonisolated struct ReportRow: Identifiable, Sendable {
    let id = UUID()
    var text: String
    var url: URL?
    var trashable = false
}

nonisolated struct ReportSection: Identifiable, Sendable {
    let id = UUID()
    var title: String
    var rows: [ReportRow]
}

nonisolated struct Report: Sendable {
    var title: String
    var summary: String
    var sections: [ReportSection]
}

// MARK: - Folder analysis (runs off the main thread)

nonisolated enum FolderAnalysis {
    struct Entry { let url: URL; let size: Int64; let date: Date }

    static let rowLimit = 300

    static func scan(_ root: URL) -> [String: Entry] {
        var out: [String: Entry] = [:]
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let en = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                                                      options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return out }
        let base = root.standardizedFileURL.path
        for case let url as URL in en {
            guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true else { continue }
            let full = url.standardizedFileURL.path
            let rel = full.hasPrefix(base + "/") ? String(full.dropFirst(base.count + 1)) : url.lastPathComponent
            out[rel] = Entry(url: url, size: Int64(v.fileSize ?? 0), date: v.contentModificationDate ?? .distantPast)
        }
        return out
    }

    static func hash(_ url: URL) -> String? {
        guard let f = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? f.close() }
        var h = SHA256()
        while true {
            guard let d = try? f.read(upToCount: 1 << 20), !d.isEmpty else { break }
            h.update(data: d)
        }
        return h.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func rows(_ items: [(String, URL)], trashable: Bool = false) -> [ReportRow] {
        var list = items.prefix(rowLimit).map { ReportRow(text: $0.0, url: $0.1, trashable: trashable) }
        if items.count > rowLimit { list.append(ReportRow(text: "… and \(items.count - rowLimit) more")) }
        return list
    }

    static func duplicates(_ root: URL) -> Report {
        let files = scan(root)
        var bySize: [Int64: [String]] = [:]
        for (rel, e) in files where e.size > 0 { bySize[e.size, default: []].append(rel) }

        var sections: [ReportSection] = []
        var wasted: Int64 = 0
        for (size, rels) in bySize where rels.count > 1 {
            var byHash: [String: [String]] = [:]
            for rel in rels {
                if let h = hash(files[rel]!.url) { byHash[h, default: []].append(rel) }
            }
            for (_, group) in byHash where group.count > 1 {
                let sorted = group.sorted()
                wasted += size * Int64(sorted.count - 1)
                let sizeText = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
                sections.append(ReportSection(
                    title: "\(URL(filePath: sorted[0]).lastPathComponent) · \(sizeText) · \(sorted.count) copies",
                    rows: sorted.map { ReportRow(text: $0, url: files[$0]!.url, trashable: true) }))
            }
        }
        sections.sort { $0.title < $1.title }
        let name = root.lastPathComponent.isEmpty ? "/" : root.lastPathComponent
        if sections.isEmpty {
            return Report(title: "Find Duplicates", summary: "No duplicate files found in \(name).", sections: [])
        }
        let w = ByteCountFormatter.string(fromByteCount: wasted, countStyle: .file)
        return Report(title: "Find Duplicates",
                      summary: "\(sections.count) groups of identical files in \(name). Removing the extra copies frees \(w).",
                      sections: sections)
    }

    static func compare(_ left: URL, _ right: URL) -> Report {
        let l = scan(left), r = scan(right)
        var leftOnly: [(String, URL)] = [], rightOnly: [(String, URL)] = [], different: [(String, URL)] = []
        var same = 0
        for (rel, e) in l {
            if let o = r[rel] {
                if e.size != o.size || abs(e.date.timeIntervalSince(o.date)) > 2 { different.append((rel, e.url)) } else { same += 1 }
            } else {
                leftOnly.append((rel, e.url))
            }
        }
        for (rel, e) in r where l[rel] == nil { rightOnly.append((rel, e.url)) }
        let sort: ((String, URL), (String, URL)) -> Bool = { $0.0 < $1.0 }
        var sections: [ReportSection] = []
        if !leftOnly.isEmpty { sections.append(ReportSection(title: "Only in left pane (\(leftOnly.count))", rows: rows(leftOnly.sorted(by: sort)))) }
        if !rightOnly.isEmpty { sections.append(ReportSection(title: "Only in right pane (\(rightOnly.count))", rows: rows(rightOnly.sorted(by: sort)))) }
        if !different.isEmpty { sections.append(ReportSection(title: "Different size or date (\(different.count))", rows: rows(different.sorted(by: sort)))) }
        let summary = sections.isEmpty
            ? "The folders match: \(same) files are the same."
            : "\(same) files are the same."
        return Report(title: "Compare Folders", summary: summary, sections: sections)
    }
}

// MARK: - Commands

extension AppModel {
    func chooseFolderAndTransfer(_ urls: Set<URL>, move: Bool) {
        guard !urls.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = move ? "Move" : "Copy"
        panel.message = move ? "Choose the folder to move the selection to" : "Choose the folder to copy the selection to"
        panel.directoryURL = active.currentURL
        guard panel.runModal() == .OK, let dir = panel.url else { return }
        dropTransfer(Array(urls), into: dir, move: move)
    }

    func openApps(for urls: Set<URL>) -> [URL] {
        guard let first = urls.sorted(by: { $0.path < $1.path }).first else { return [] }
        return Array(NSWorkspace.shared.urlsForApplications(toOpen: first).prefix(25))
    }

    func open(_ urls: Set<URL>, with appURL: URL) {
        NSWorkspace.shared.open(Array(urls), withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
    }

    func findDuplicates() {
        let root = active.currentURL
        report = Report(title: "Find Duplicates", summary: "Scanning…", sections: [])
        Task {
            let result = await Task.detached { FolderAnalysis.duplicates(root) }.value
            if report != nil { report = result }
        }
    }

    func compareFolders() {
        guard dual else {
            alert = "Open the second pane to compare folders."
            return
        }
        let left = groups[0].current.currentURL, right = groups[1].current.currentURL
        report = Report(title: "Compare Folders", summary: "Comparing…", sections: [])
        Task {
            let result = await Task.detached { FolderAnalysis.compare(left, right) }.value
            if report != nil { report = result }
        }
    }

    func trashFromReport(_ row: ReportRow) {
        guard let url = row.url else { return }
        trash([url])
        guard var r = report else { return }
        for i in r.sections.indices { r.sections[i].rows.removeAll { $0.id == row.id } }
        r.sections.removeAll { $0.rows.count < 2 && $0.title.contains("copies") }
        report = r
    }
}

// MARK: - Result panel

struct ReportPanel: View {
    let app: AppModel
    @Environment(\.closePanel) private var close
    @AppStorage("textSize") private var textSize = 1
    private var s: CGFloat { UIScale.value(textSize) }

    var body: some View {
        let report = app.report
        VStack(alignment: .leading, spacing: 14) {
            Text(report?.title ?? "").font(.system(size: 22 * s))
            Text(report?.summary ?? "").foregroundStyle(.secondary)
            if let sections = report?.sections, !sections.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14 * s) {
                        ForEach(sections) { section in
                            VStack(alignment: .leading, spacing: 4 * s) {
                                Text(section.title).fontWeight(.semibold)
                                ForEach(section.rows) { row in
                                    HStack(spacing: 8) {
                                        Text(row.text).lineLimit(1).truncationMode(.middle)
                                        Spacer(minLength: 8)
                                        if let url = row.url {
                                            Button("Show") { app.active.navigate(to: url.deletingLastPathComponent()); close() }
                                                .buttonStyle(.plain).foregroundStyle(Color.filetor)
                                            if row.trashable {
                                                Button("Trash") { app.trashFromReport(row) }
                                                    .buttonStyle(.plain).foregroundStyle(Color.filetor)
                                            }
                                        }
                                    }
                                    .font(.system(size: 12.5 * s))
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 380 * s)
            }
            HStack {
                if report?.title == "Compare Folders", report?.sections.isEmpty == false {
                    Button("Synchronize…") { close(); app.synchronize() }
                        .buttonStyle(PathsButtonStyle(scale: s, prominent: false))
                }
                Spacer()
                Button("Done") { close() }
                    .buttonStyle(PathsButtonStyle(scale: s, prominent: true))
                    .keyboardShortcut(.defaultAction)
                    .background { Button("") { close() }.keyboardShortcut(.cancelAction).opacity(0).frame(width: 0, height: 0) }
            }
        }
        .font(.system(size: 13 * s))
        .padding(28)
        .frame(width: 640 * s)
    }
}

// MARK: - Synchronize

nonisolated struct SyncSide: Sendable {
    let url: URL
    let size: Int64
    let date: Date
}

nonisolated enum SyncAction: Sendable { case toRight, toLeft, skip }

nonisolated enum SyncDirection: String, CaseIterable, Sendable {
    case both = "Both ways", leftToRight = "Left to right", rightToLeft = "Right to left"
}

nonisolated struct SyncRow: Identifiable, Sendable {
    let rel: String
    let left: SyncSide?
    let right: SyncSide?
    var action: SyncAction = .skip
    var id: String { rel }
    var isOneSided: Bool { left == nil || right == nil }

    func defaultAction(_ d: SyncDirection) -> SyncAction {
        switch (left, right) {
        case (.some, nil): return d == .rightToLeft ? .skip : .toRight
        case (nil, .some): return d == .leftToRight ? .skip : .toLeft
        case (let l?, let r?):
            if abs(l.date.timeIntervalSince(r.date)) <= 2 { return .skip }
            let leftNewer = l.date > r.date
            switch d {
            case .both: return leftNewer ? .toRight : .toLeft
            case .leftToRight: return leftNewer ? .toRight : .skip
            case .rightToLeft: return leftNewer ? .skip : .toLeft
            }
        default: return .skip
        }
    }

    /// The actions a click on the pill cycles through.
    var choices: [SyncAction] {
        if left != nil && right != nil { return [.toRight, .toLeft, .skip] }
        return left != nil ? [.toRight, .skip] : [.toLeft, .skip]
    }
}

nonisolated extension FolderAnalysis {
    static func syncRows(_ leftRoot: URL, _ rightRoot: URL) -> [SyncRow] {
        let l = scan(leftRoot), r = scan(rightRoot)
        var rows: [SyncRow] = []
        for rel in Set(l.keys).union(r.keys) {
            let le = l[rel].map { SyncSide(url: $0.url, size: $0.size, date: $0.date) }
            let re = r[rel].map { SyncSide(url: $0.url, size: $0.size, date: $0.date) }
            if let a = le, let b = re, a.size == b.size, abs(a.date.timeIntervalSince(b.date)) <= 2 { continue }
            rows.append(SyncRow(rel: rel, left: le, right: re))
        }
        return rows.sorted { $0.rel.localizedStandardCompare($1.rel) == .orderedAscending }
    }
}

@Observable
final class SyncSession {
    let leftRoot: URL
    let rightRoot: URL
    var rows: [SyncRow] = []
    var loading = true
    var direction = SyncDirection.both

    init(left: URL, right: URL) { leftRoot = left; rightRoot = right }

    func applyDirection() {
        for i in rows.indices { rows[i].action = rows[i].defaultAction(direction) }
    }

    func cycle(_ id: String) {
        guard let i = rows.firstIndex(where: { $0.id == id }) else { return }
        let c = rows[i].choices
        let at = c.firstIndex(of: rows[i].action) ?? c.count - 1
        rows[i].action = c[(at + 1) % c.count]
    }

    func count(_ a: SyncAction) -> Int { rows.filter { $0.action == a }.count }
}

extension AppModel {
    func synchronize() {
        guard dual else {
            alert = "Open the second pane to synchronize folders."
            return
        }
        let left = groups[0].current.currentURL, right = groups[1].current.currentURL
        guard left.standardizedFileURL != right.standardizedFileURL else {
            alert = "Both panes show the same folder."
            return
        }
        let session = SyncSession(left: left, right: right)
        sync = session
        Task {
            let rows = await Task.detached { FolderAnalysis.syncRows(left, right) }.value
            guard sync === session else { return }
            session.rows = rows
            session.applyDirection()
            session.loading = false
        }
    }

    func runSync(_ session: SyncSession) {
        func items(_ action: SyncAction) -> [(src: URL, dstDir: URL)] {
            var out: [(src: URL, dstDir: URL)] = []
            for row in session.rows where row.action == action {
                guard let src = action == .toRight ? row.left?.url : row.right?.url else { continue }
                let root = action == .toRight ? session.rightRoot : session.leftRoot
                let dir = root.appending(path: row.rel).deletingLastPathComponent()
                do { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
                catch { alert = error.localizedDescription; continue }
                out.append((src: src, dstDir: dir))
            }
            return out
        }
        let right = items(.toRight), left = items(.toLeft)
        sync = nil
        transfers.start(items: right, move: false, conflict: .replace)
        transfers.start(items: left, move: false, conflict: .replace)
    }
}

struct SyncPanel: View {
    let app: AppModel
    var body: some View {
        if let session = app.sync { SyncContent(app: app, session: session) }
    }
}

struct SyncContent: View {
    let app: AppModel
    @Bindable var session: SyncSession
    @Environment(\.closePanel) private var close
    @AppStorage("textSize") private var textSize = 1
    private var s: CGFloat { UIScale.value(textSize) }

    private func size(_ side: SyncSide?) -> String {
        side.map { ByteCountFormatter.string(fromByteCount: $0.size, countStyle: .file) } ?? "--"
    }
    private func date(_ side: SyncSide?) -> String {
        side.map { $0.date.formatted(.dateTime.day().month(.abbreviated).year()) } ?? "--"
    }
    private func arrow(_ a: SyncAction) -> String {
        switch a {
        case .toRight: return "→"
        case .toLeft: return "←"
        case .skip: return "Skip"
        }
    }

    private func columns(_ path: some View, _ ls: some View, _ ld: some View, _ act: some View,
                         _ rs: some View, _ rd: some View) -> some View {
        HStack(spacing: 10) {
            path.frame(maxWidth: .infinity, alignment: .leading)
            ls.frame(width: 70 * s, alignment: .trailing)
            ld.frame(width: 110 * s, alignment: .leading)
            act.frame(width: 64 * s)
            rs.frame(width: 70 * s, alignment: .trailing)
            rd.frame(width: 110 * s, alignment: .leading)
        }
    }

    private func section(_ title: String, _ rows: [SyncRow]) -> some View {
        VStack(alignment: .leading, spacing: 2 * s) {
            if !rows.isEmpty {
                Text("\(title) (\(rows.count))").fontWeight(.semibold).padding(.vertical, 4 * s)
                ForEach(rows) { row in
                    columns(
                        Text(row.rel).lineLimit(1).truncationMode(.middle),
                        Text(size(row.left)),
                        Text(date(row.left)).foregroundStyle(.secondary),
                        Button { session.cycle(row.id) } label: {
                            Text(arrow(row.action))
                                .frame(minWidth: 52 * s)
                                .padding(.vertical, 2 * s)
                                .background(row.action == .skip ? Color.primary.opacity(0.07) : Color.filetor.opacity(0.16),
                                            in: RoundedRectangle(cornerRadius: 7))
                        }
                        .buttonStyle(.plain),
                        Text(size(row.right)),
                        Text(date(row.right)).foregroundStyle(.secondary)
                    )
                    .font(.system(size: 12.5 * s))
                }
            }
        }
    }

    var body: some View {
        let toRight = session.count(.toRight), toLeft = session.count(.toLeft)
        VStack(alignment: .leading, spacing: 12) {
            Text("Synchronize").font(.system(size: 22 * s))
            VStack(alignment: .leading, spacing: 2) {
                Text("Left: \(session.leftRoot.path)")
                Text("Right: \(session.rightRoot.path)")
            }
            .font(.system(size: 12.5 * s))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)

            HStack {
                Text("Direction")
                Picker("", selection: Binding(get: { session.direction },
                                              set: { session.direction = $0; session.applyDirection() })) {
                    ForEach(SyncDirection.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }

            if session.loading {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Comparing…").foregroundStyle(.secondary) }
                    .frame(maxWidth: .infinity, minHeight: 80 * s)
            } else if session.rows.isEmpty {
                Text("The folders are already in sync.").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80 * s)
            } else {
                columns(Text("Path"), Text("Left size"), Text("Left modified"), Text("Action"),
                        Text("Right size"), Text("Right modified"))
                    .font(.system(size: 12 * s))
                    .foregroundStyle(.secondary)
                Divider()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2 * s) {
                        section("Only on one side", session.rows.filter(\.isOneSided))
                        section("Different", session.rows.filter { !$0.isOneSided })
                    }
                }
                .frame(height: 320 * s)
                Text("Newer files replace older ones, and replaced files are moved to the Trash. Nothing is deleted.")
                    .font(.system(size: 12 * s))
                    .foregroundStyle(.secondary)
            }

            HStack {
                if !session.loading && !session.rows.isEmpty {
                    Text("\(toRight) copy to the right, \(toLeft) copy to the left, \(session.count(.skip)) skipped")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { close() }
                    .buttonStyle(PathsButtonStyle(scale: s, prominent: false))
                    .keyboardShortcut(.cancelAction)
                Button("Synchronize") { app.runSync(session) }
                    .buttonStyle(PathsButtonStyle(scale: s, prominent: true))
                    .keyboardShortcut(.defaultAction)
                    .disabled(session.loading || toRight + toLeft == 0)
            }
        }
        .font(.system(size: 13 * s))
        .padding(28)
        .frame(width: 860 * s)
    }
}
