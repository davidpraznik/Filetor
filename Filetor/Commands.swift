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

@MainActor private var sharePickerHolder: NSSharingServicePicker?

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

    func share(_ urls: Set<URL>) {
        guard !urls.isEmpty, let view = NSApp.keyWindow?.contentView else { return }
        let picker = NSSharingServicePicker(items: urls.sorted { $0.path < $1.path })
        sharePickerHolder = picker
        picker.show(relativeTo: NSRect(x: view.bounds.midX, y: view.bounds.maxY - 60, width: 1, height: 1), of: view, preferredEdge: .minY)
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
