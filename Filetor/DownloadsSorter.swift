import Foundation
import Observation

/// One rule of the Downloads sorting: a file whose extension or name matches goes to `folder`.
struct SortRule: Codable, Identifiable, Hashable {
    enum Kind: String, Codable { case ext, name }
    var id = UUID()
    var kind: Kind = .ext
    /// Extensions without a dot, separated by commas ("jpg, png"), or a part of the file name.
    var value = ""
    /// Folder inside Downloads, or an absolute path (also "~/…").
    var folder = ""
}

/// Sorts the files in the chosen folders (Downloads by default) into subfolders, the ones already there and the ones that arrive later. Off by default.
@Observable
final class DownloadsSorter {
    static let enabledKey = "sortDownloads"
    static let rulesKey = "sortRules"
    static let foldersKey = "sortFolders"

    /// Folders that are sorted. Downloads until the user chooses others.
    static var folders: [URL] {
        get {
            if let paths = UserDefaults.standard.stringArray(forKey: foldersKey) {
                return paths.map { URL(filePath: $0, directoryHint: .isDirectory) }
            }
            return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)
        }
        set {
            UserDefaults.standard.set(newValue.map(\.path), forKey: foldersKey)
        }
    }

    /// Looks at the folders now (after the switch was turned on or a folder was added).
    func rescan() { scan(report: true) }

    /// Called after a batch was moved: the notice text and a closure that moves everything back.
    @ObservationIgnored var onMoved: ((String, @escaping () -> String?) -> Void)?
    /// Called with a plain notice (nothing to sort, folder cannot be read).
    @ObservationIgnored var onNote: ((String) -> Void)?
    @ObservationIgnored private var timer: Timer?
    /// Folders that could not be read, so the notice appears once, not every 5 seconds.
    @ObservationIgnored private var unreadable: Set<String> = []

    var isEnabled: Bool { UserDefaults.standard.bool(forKey: Self.enabledKey) }

    func setEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: Self.enabledKey)
        if on {
            start()
            scan(report: true)
        } else {
            stop()
        }
    }

    func start() {
        guard isEnabled, timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.scan() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: Rules

    static var rules: [SortRule] {
        get {
            guard let data = UserDefaults.standard.data(forKey: rulesKey),
                  let list = try? JSONDecoder().decode([SortRule].self, from: data) else { return [] }
            return list
        }
        set {
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: rulesKey)
        }
    }

    /// The fixed folders by type (used when no rule of the user matches).
    static let typeFolders: [(folder: String, extensions: Set<String>)] = [
        ("Images", ["jpg", "jpeg", "png", "gif", "heic", "heif", "webp", "tif", "tiff", "bmp", "svg", "raw", "cr2", "nef", "arw", "dng"]),
        ("Documents", ["pdf", "doc", "docx", "txt", "rtf", "pages", "odt", "md", "epub", "xls", "xlsx", "numbers", "csv", "ppt", "pptx", "key", "odp", "ods"]),
        ("Archives", ["zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz"]),
        ("Installers", ["dmg", "pkg", "mpkg"]),
        ("Video", ["mp4", "mov", "mkv", "avi", "webm", "m4v", "wmv"]),
        ("Audio", ["mp3", "wav", "aac", "flac", "m4a", "aiff", "aif", "ogg", "opus"]),
        ("3D Models", ["3mf", "stl", "obj", "step", "stp", "gcode", "fbx", "blend"]),
        ("Fonts", ["otf", "ttf", "woff", "woff2"]),
        ("Design", ["fig", "ai", "psd", "psb", "indd", "indt", "idml", "sketch", "xd", "eps", "cdr", "xcf", "kra", "clip", "pxd",
                    "af", "afdesign", "afphoto", "afpub", "aftemplate", "vectorcraft"]),
        ("Scripts", ["jsx", "jsxbin", "py", "sh", "scpt", "applescript"])
    ]

    /// Extensions of files that are still being downloaded.
    private static let partial: Set<String> = ["download", "crdownload", "part", "partial", "opdownload", "tmp", "filepart"]

    /// The folder a file goes to, or nil when it stays where it is.
    static func destination(for url: URL, downloads: URL) -> URL? {
        let ext = url.pathExtension.lowercased()
        let name = url.lastPathComponent.lowercased()
        for rule in rules where !rule.folder.trimmingCharacters(in: .whitespaces).isEmpty {
            let value = rule.value.lowercased().trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty else { continue }
            let hit: Bool
            switch rule.kind {
            case .ext:
                hit = value.split(separator: ",").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ". ")) }.contains(ext)
            case .name:
                hit = name.contains(value)
            }
            if hit { return folderURL(rule.folder, downloads: downloads) }
        }
        for t in typeFolders where t.extensions.contains(ext) {
            return downloads.appending(path: t.folder, directoryHint: .isDirectory)
        }
        return nil
    }

    private static func folderURL(_ folder: String, downloads: URL) -> URL {
        let f = folder.trimmingCharacters(in: .whitespaces)
        if f.hasPrefix("/") || f.hasPrefix("~") {
            return URL(filePath: (f as NSString).expandingTildeInPath, directoryHint: .isDirectory)
        }
        return downloads.appending(path: f, directoryHint: .isDirectory)
    }

    // MARK: Scan

    private struct Move { let from: URL; let to: URL }

    private func scan(report: Bool = false) {
        guard isEnabled else { return }
        let keys: [URLResourceKey] = [.isDirectoryKey, .creationDateKey, .contentModificationDateKey]
        let fm = FileManager.default
        var moves: [Move] = []
        // A folder on a disk that is not connected is skipped until the disk is back.
        for downloads in Self.folders {
        let items: [URL]
        do {
            items = try fm.contentsOfDirectory(
                at: downloads, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
            unreadable.remove(downloads.path)
        } catch {
            if report || !unreadable.contains(downloads.path) {
                let hint = (error as NSError).code == NSFileReadNoPermissionError
                    ? " Allow Filetor access in System Settings > Privacy & Security (Files and Folders or Full Disk Access)."
                    : ""
                onNote?("Cannot read \(downloads.lastPathComponent).\(hint)")
            }
            unreadable.insert(downloads.path)
            continue
        }
        var found = 0
        defer { if report && found == 0 && !unreadable.contains(downloads.path) { onNote?("Nothing to sort in \(downloads.lastPathComponent)") } }
        for url in items {
            let v = try? url.resourceValues(forKeys: Set(keys))
            if v?.isDirectory ?? true { continue }
            if Self.partial.contains(url.pathExtension.lowercased()) { continue }
            // Files that are still changing (being downloaded or copied) wait for the next round.
            if let modified = v?.contentModificationDate, Date().timeIntervalSince(modified) < 6 { continue }
            guard let folder = Self.destination(for: url, downloads: downloads) else { continue }
            found += 1
            do {
                try fm.createDirectory(at: folder, withIntermediateDirectories: true)
                let target = Self.uniqueURL(folder.appending(path: url.lastPathComponent))
                try fm.moveItem(at: url, to: target)
                moves.append(Move(from: url, to: target))
            } catch {
                continue
            }
        }
        }
        guard !moves.isEmpty else { return }
        let text: String
        if moves.count == 1, let m = moves.first {
            text = "Moved \(m.from.lastPathComponent) to \(m.to.deletingLastPathComponent().lastPathComponent)"
        } else {
            text = "Moved \(moves.count) files into folders"
        }
        onMoved?(text) {
            var failed = 0
            for m in moves.reversed() {
                do { try FileManager.default.moveItem(at: m.to, to: Self.uniqueURL(m.from)) } catch { failed += 1 }
            }
            return failed == 0 ? nil : "\(failed) file(s) could not be moved back."
        }
    }

    /// `name 2.ext`, `name 3.ext`… when the name is taken. Never overwrites.
    private static func uniqueURL(_ url: URL) -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return url }
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        let dir = url.deletingLastPathComponent()
        var n = 2
        while true {
            let name = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            let candidate = dir.appending(path: name)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            n += 1
        }
    }
}
