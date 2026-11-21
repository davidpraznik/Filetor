import SwiftUI
import UniformTypeIdentifiers

// MARK: - Model

nonisolated struct PreviewEntry: Identifiable, Sendable {
    /// Full path of a folder item, or the path inside the archive.
    let path: String
    let name: String
    let isDirectory: Bool
    let size: Int64?
    let date: Date?
    let depth: Int
    var id: String { path }
}

nonisolated enum ArchiveKind {
    static func isArchive(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if ["zip", "tar", "tgz", "tbz", "tbz2", "txz", "7z", "rar"].contains(ext) { return true }
        if ["gz", "bz2", "xz"].contains(ext) { return url.deletingPathExtension().pathExtension.lowercased() == "tar" }
        return false
    }
}

// MARK: - Folder listing

nonisolated enum FolderPreview {
    static func list(_ url: URL) -> [PreviewEntry]? {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .fileSizeKey, .contentModificationDateKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return nil }
        let items = urls.map { u -> PreviewEntry in
            let v = try? u.resourceValues(forKeys: Set(keys))
            let dir = (v?.isDirectory ?? false) && !(v?.isPackage ?? false)
            return PreviewEntry(path: u.path, name: u.lastPathComponent, isDirectory: dir,
                                size: dir ? nil : Int64(v?.fileSize ?? 0), date: v?.contentModificationDate, depth: 0)
        }
        return items.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}

// MARK: - Archive listing (read only, nothing is extracted)

nonisolated enum ArchiveListing {
    nonisolated struct Raw { let path: String; let isDir: Bool; let size: Int64; let date: Date? }
    nonisolated struct Result { let entries: [PreviewEntry]; let files: Int; let unpacked: Int64; let truncated: Bool }

    static let rowLimit = 5000

    static func list(_ url: URL) -> Result? {
        let raws: [Raw]?
        if url.pathExtension.lowercased() == "zip" { raws = zipList(url) } else { raws = tarList(url) }
        guard let raws, !raws.isEmpty else { return nil }
        return tree(raws)
    }

    private static func run(_ exe: String, _ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        if data.isEmpty { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    private static func zipList(_ url: URL) -> [Raw]? {
        guard let text = run("/usr/bin/zipinfo", ["-l", "-T", url.path]) else { return nil }
        var out: [Raw] = []
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 8, omittingEmptySubsequences: true)
            guard parts.count == 9, let size = Int64(parts[3]), let perms = parts[0].first, "-dl".contains(perms) else { continue }
            let name = String(parts[8])
            out.append(Raw(path: name, isDir: perms == "d" || name.hasSuffix("/"), size: size, date: zipDate(String(parts[7]))))
        }
        return out
    }

    private static func zipDate(_ token: String) -> Date? {
        let left = token.split(separator: ".").first.map(String.init) ?? token
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = left.count == 8 ? "yyyyMMdd" : "yyMMdd"
        return f.date(from: left)
    }

    private static func tarList(_ url: URL) -> [Raw]? {
        guard let text = run("/usr/bin/tar", ["-tvf", url.path]) else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        let now = Date()
        let year = Calendar.current.component(.year, from: now)
        var out: [Raw] = []
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 8, omittingEmptySubsequences: true)
            guard parts.count == 9, let size = Int64(parts[4]), let perms = parts[0].first, "-dlh".contains(perms) else { continue }
            var name = String(parts[8])
            if perms == "l", let r = name.range(of: " -> ") { name = String(name[..<r.lowerBound]) }
            let when = String(parts[7])
            var date: Date?
            if when.contains(":") {
                f.dateFormat = "MMM d HH:mm yyyy"
                date = f.date(from: "\(parts[5]) \(parts[6]) \(when) \(year)")
                if let d = date, d > now { date = f.date(from: "\(parts[5]) \(parts[6]) \(when) \(year - 1)") }
            } else {
                f.dateFormat = "MMM d yyyy"
                date = f.date(from: "\(parts[5]) \(parts[6]) \(when)")
            }
            out.append(Raw(path: name, isDir: perms == "d" || name.hasSuffix("/"), size: size, date: date))
        }
        return out
    }

    /// Builds the folder tree: missing parent folders are added, folders come first, sizes add up.
    private static func tree(_ raws: [Raw]) -> Result {
        struct Node { var isDir: Bool; var size: Int64; var date: Date? }
        var nodes: [String: Node] = [:]
        var children: [String: [String]] = [:]
        var files = 0
        var unpacked: Int64 = 0

        func ensure(_ path: String, isDir: Bool, size: Int64, date: Date?) {
            if nodes[path] == nil {
                nodes[path] = Node(isDir: isDir, size: size, date: date)
                let parent = path.contains("/") ? String(path[..<path.lastIndex(of: "/")!]) : ""
                children[parent, default: []].append(path)
            } else if isDir {
                nodes[path]?.isDir = true
                if nodes[path]?.date == nil { nodes[path]?.date = date }
            }
        }

        for r in raws {
            var path = r.path
            while path.hasPrefix("./") { path.removeFirst(2) }
            while path.hasSuffix("/") { path.removeLast() }
            if path.isEmpty || path.hasPrefix("__MACOSX") { continue }
            let comps = path.split(separator: "/").map(String.init)
            var prefix = ""
            for (i, c) in comps.enumerated() {
                prefix = prefix.isEmpty ? c : prefix + "/" + c
                let last = i == comps.count - 1
                if last { ensure(prefix, isDir: r.isDir, size: r.isDir ? 0 : r.size, date: r.date) }
                else { ensure(prefix, isDir: true, size: 0, date: nil) }
            }
            if !r.isDir { files += 1; unpacked += r.size }
        }

        // Folder sizes.
        for r in raws where !r.isDir {
            var path = r.path
            while path.hasPrefix("./") { path.removeFirst(2) }
            let comps = path.split(separator: "/").map(String.init)
            var prefix = ""
            for c in comps.dropLast() {
                prefix = prefix.isEmpty ? c : prefix + "/" + c
                nodes[prefix]?.size += r.size
            }
        }

        var out: [PreviewEntry] = []
        var truncated = false
        func walk(_ parent: String, depth: Int) {
            let kids = (children[parent] ?? []).sorted { a, b in
                let da = nodes[a]!.isDir, db = nodes[b]!.isDir
                if da != db { return da }
                return a.localizedStandardCompare(b) == .orderedAscending
            }
            for k in kids {
                if out.count >= rowLimit { truncated = true; return }
                let n = nodes[k]!
                out.append(PreviewEntry(path: k, name: String(k.split(separator: "/").last ?? ""), isDirectory: n.isDir,
                                        size: n.size, date: n.date, depth: depth))
                if n.isDir { walk(k, depth: depth + 1) }
            }
        }
        walk("", depth: 0)
        return Result(entries: out, files: files, unpacked: unpacked, truncated: truncated)
    }
}

// MARK: - Panel

struct SpacePreviewPanel: View {
    let app: AppModel
    let url: URL
    @Environment(\.closePanel) private var close
    @AppStorage("textSize") private var textSize = 1
    @State private var folder: URL
    @State private var history: [URL] = []
    @State private var entries: [PreviewEntry] = []
    @State private var loading = true
    @State private var failed = false
    @State private var truncated = false
    @State private var files = 0
    @State private var unpacked: Int64 = 0
    @State private var selected: String?
    @State private var expanded: Set<String> = []

    init(app: AppModel, url: URL) {
        self.app = app
        self.url = url
        _folder = State(initialValue: url)
    }

    private var s: CGFloat { UIScale.value(textSize) }
    private var isArchive: Bool { ArchiveKind.isArchive(url) }

    private var visible: [PreviewEntry] {
        guard isArchive else { return entries }
        return entries.filter { e in
            let comps = e.path.split(separator: "/")
            var prefix = ""
            for c in comps.dropLast() {
                prefix = prefix.isEmpty ? String(c) : prefix + "/" + c
                if !expanded.contains(prefix) { return false }
            }
            return true
        }
    }

    private var title: String { isArchive ? url.lastPathComponent : folder.lastPathComponent }

    private var summary: String {
        if loading { return "Reading…" }
        if failed { return isArchive ? "This archive could not be read." : "This folder could not be read." }
        if isArchive {
            let unp = ByteCountFormatter.string(fromByteCount: unpacked, countStyle: .file)
            let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            let zipped = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
            return "\(files) files, \(unp) unpacked, \(zipped) packed" + (truncated ? ". Showing the first \(ArchiveListing.rowLimit) entries" : "")
        }
        let parent = (folder.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
        return "\(parent), \(entries.count) \(entries.count == 1 ? "item" : "items")"
    }

    private func load() async {
        loading = true
        failed = false
        let target = folder
        let archive = isArchive
        if archive {
            let r = await Task.detached(priority: .userInitiated) { ArchiveListing.list(url) }.value
            if let r {
                entries = r.entries; files = r.files; unpacked = r.unpacked; truncated = r.truncated
                expanded = r.entries.count <= 300 ? Set(r.entries.filter(\.isDirectory).map(\.path)) : []
            } else { entries = []; failed = true }
        } else {
            let r = await Task.detached(priority: .userInitiated) { FolderPreview.list(target) }.value
            if let r { entries = r } else { entries = []; failed = true }
        }
        selected = nil
        loading = false
    }

    private func activate(_ e: PreviewEntry) {
        if isArchive {
            if e.isDirectory { if expanded.contains(e.path) { expanded.remove(e.path) } else { expanded.insert(e.path) } }
        } else if e.isDirectory {
            history.append(folder)
            folder = URL(fileURLWithPath: e.path)
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: e.path))
        }
    }

    private func icon(_ e: PreviewEntry) -> NSImage {
        if !isArchive { return ThemedFolderIcon.icon(forFile: URL(fileURLWithPath: e.path), side: 18 * s) }
        if e.isDirectory { return NSWorkspace.shared.icon(for: .folder) }
        let ext = (e.name as NSString).pathExtension
        return NSWorkspace.shared.icon(for: UTType(filenameExtension: ext) ?? .data)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                if !isArchive && !history.isEmpty {
                    Button { folder = history.removeLast() } label: {
                        Image(systemName: "chevron.left").font(.system(size: 13 * s, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.filetor)
                    .help("Back")
                }
                Image(nsImage: isArchive ? NSWorkspace.shared.icon(forFile: url.path) : ThemedFolderIcon.icon(forFile: folder, side: 28 * s))
                    .resizable().frame(width: 28 * s, height: 28 * s)
                Text(title).font(.system(size: 20 * s, weight: .medium)).lineLimit(1).truncationMode(.middle)
                if isArchive {
                    Text("Read only")
                        .font(.system(size: 11.5 * s))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7).padding(.vertical, 1)
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.18)))
                }
            }
            Text(summary).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            if !entries.isEmpty {
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        Text("Name").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Date Modified").frame(width: 120 * s, alignment: .leading)
                        Text("Size").frame(width: 80 * s, alignment: .trailing)
                    }
                    .font(.system(size: 12 * s, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 6)
                    Divider()
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(visible) { e in
                                row(e)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .frame(height: 300 * s)
                }
            }
            HStack {
                Text(isArchive ? "Space or Esc closes." : "Double-click opens an item. Space or Esc closes.")
                    .font(.system(size: 12 * s)).foregroundStyle(.tertiary)
                Spacer()
                if !isArchive {
                    Button("Open Folder") { app.active.navigate(to: folder); close() }
                        .buttonStyle(PathsButtonStyle(scale: s))
                }
                Button("Done") { close() }
                    .buttonStyle(PathsButtonStyle(scale: s, prominent: true))
                    .keyboardShortcut(.defaultAction)
                    .background { Button("") { close() }.keyboardShortcut(.cancelAction).opacity(0).frame(width: 0, height: 0) }
                    .background { Button("") { close() }.keyboardShortcut(.space, modifiers: []).opacity(0).frame(width: 0, height: 0) }
            }
        }
        .font(.system(size: 13 * s))
        .padding(.horizontal, 26).padding(.top, 24).padding(.bottom, 20)
        .frame(width: 640 * s)
        .task(id: folder) { await load() }
    }

    private func row(_ e: PreviewEntry) -> some View {
        let on = selected == e.path
        return HStack(spacing: 10) {
            HStack(spacing: 7) {
                if isArchive {
                    Group {
                        if e.isDirectory {
                            Image(systemName: expanded.contains(e.path) ? "chevron.down" : "chevron.right")
                                .font(.system(size: 9 * s, weight: .semibold))
                        } else { Color.clear }
                    }
                    .frame(width: 10 * s)
                }
                Image(nsImage: icon(e)).resizable().frame(width: 17 * s, height: 17 * s)
                Text(e.name).lineLimit(1).truncationMode(.middle)
            }
            .padding(.leading, CGFloat(e.depth) * 18 * s)
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(e.date?.formatted(date: .abbreviated, time: .omitted) ?? "")
                .foregroundStyle(on ? Color.white.opacity(0.85) : Color.secondary)
                .frame(width: 120 * s, alignment: .leading)
            Text(e.size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "")
                .frame(width: 80 * s, alignment: .trailing)
        }
        .font(.system(size: 12.5 * s))
        .foregroundStyle(on ? Color.white : Color.primary)
        .padding(.vertical, 5 * s)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(on ? Color.filetor : Color.clear))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { activate(e) }
        .onTapGesture { selected = e.path }
    }
}
