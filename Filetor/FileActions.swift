import Foundation

/// Helpers that run outside the main actor (archives, folder sizes).
nonisolated enum FileTools {
    static func run(_ exe: String, _ args: [String], cwd: URL? = nil) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        p.currentDirectoryURL = cwd
        let pipe = Pipe()
        p.standardError = pipe
        p.standardOutput = FileHandle.nullDevice
        do { try p.run() } catch { return error.localizedDescription }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        if p.terminationStatus == 0 { return nil }
        let text = String(data: data, encoding: .utf8) ?? ""
        return text.isEmpty ? "The command failed." : text
    }

    static func exists(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }

    static func unique(_ url: URL) -> URL {
        guard exists(url) else { return url }
        let dir = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var n = 2
        var candidate = url
        repeat {
            let name = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            candidate = dir.appending(path: name)
            n += 1
        } while exists(candidate)
        return candidate
    }

    static func compress(_ urls: [URL], in dir: URL) -> String? {
        guard let first = urls.first else { return nil }
        if urls.count == 1 {
            let dest = unique(dir.appending(path: first.lastPathComponent + ".zip"))
            return run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", first.path, dest.path])
        }
        let dest = unique(dir.appending(path: "Archive.zip"))
        return run("/usr/bin/zip", ["-r", "-y", dest.path] + urls.map(\.lastPathComponent), cwd: dir)
    }

    static func decompress(_ urls: [URL], in dir: URL) -> String? {
        var errors: [String] = []
        for url in urls {
            let dest = unique(dir.appending(path: url.deletingPathExtension().lastPathComponent))
            do { try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: false) }
            catch { errors.append("\(url.lastPathComponent): \(error.localizedDescription)"); continue }
            let err: String?
            if url.pathExtension.lowercased() == "zip" {
                err = run("/usr/bin/ditto", ["-x", "-k", url.path, dest.path])
            } else {
                err = run("/usr/bin/tar", ["-xf", url.path, "-C", dest.path])
            }
            if let err { errors.append("\(url.lastPathComponent): \(err)") }
        }
        return errors.isEmpty ? nil : errors.joined(separator: "\n")
    }

    static func size(of url: URL) -> Int64 {
        let v = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
        guard v?.isDirectory == true && v?.isSymbolicLink != true else { return Int64(v?.fileSize ?? 0) }
        var total: Int64 = 0
        if let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) {
            for case let u as URL in e {
                let r = try? u.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                if r?.isRegularFile == true { total += Int64(r?.fileSize ?? 0) }
            }
        }
        return total
    }
}
