import Foundation
import Darwin

// MARK: - Shared value types (no actor isolation, used from background work)

nonisolated struct ConflictInfo: Sendable {
    let name: String
    let srcIsDir: Bool
    let dstIsDir: Bool
    let srcSize: Int64
    let dstSize: Int64
    let srcDate: Date?
    let dstDate: Date?
}

nonisolated enum ConflictChoice: Sendable {
    case replace, keepBoth, merge, skip, stop
}

nonisolated struct ConflictAnswer: Sendable {
    let choice: ConflictChoice
    let applyToAll: Bool
}

/// Thread-safe state shared between the background engine and the UI.
nonisolated final class TransferControl: @unchecked Sendable {
    private let lock = NSLock()
    private var _cancelled = false
    private var _done: Int64 = 0
    private var _total: Int64 = 1
    private var _name = ""

    var cancelled: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _cancelled }
        set { lock.lock(); _cancelled = newValue; lock.unlock() }
    }
    func add(_ delta: Int64) { lock.lock(); _done += delta; lock.unlock() }
    func setTotal(_ v: Int64) { lock.lock(); _total = max(v, 1); lock.unlock() }
    func setName(_ n: String) { lock.lock(); _name = n; lock.unlock() }
    var snapshot: (done: Int64, total: Int64, name: String) {
        lock.lock(); defer { lock.unlock() }
        return (_done, _total, _name)
    }
}

nonisolated private final class CopyContext {
    let control: TransferControl
    var last: Int64 = 0
    init(control: TransferControl) { self.control = control }
    func report(_ copied: Int64) {
        let delta = copied - last
        last = copied
        if delta > 0 { control.add(delta) }
    }
}

// MARK: - Engine

nonisolated final class TransferEngine: @unchecked Sendable {
    private let move: Bool
    private let control: TransferControl
    private let ask: @Sendable (ConflictInfo) async -> ConflictAnswer
    private var sticky: ConflictChoice?
    private let fm = FileManager.default

    init(move: Bool,
         control: TransferControl,
         ask: @escaping @Sendable (ConflictInfo) async -> ConflictAnswer) {
        self.move = move
        self.control = control
        self.ask = ask
    }

    /// Returns a list of human readable failures (empty when everything went fine).
    func run(items: [(src: URL, dstDir: URL)]) async -> [String] {
        var failures: [String] = []
        var total: Int64 = 0
        for item in items { total += size(of: item.src) }
        control.setTotal(total)

        for item in items {
            if control.cancelled { break }
            do {
                try await process(item.src, into: item.dstDir)
            } catch is CancellationError {
                control.cancelled = true
                break
            } catch {
                failures.append("\(item.src.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return failures
    }

    // MARK: Core logic

    private func process(_ src: URL, into dstDir: URL) async throws {
        if control.cancelled { throw CancellationError() }
        let name = src.lastPathComponent
        control.setName(name)
        var dst = dstDir.appending(path: name)

        if dstDir.standardizedFileURL.path.hasPrefix(src.standardizedFileURL.path + "/") {
            throw NSError(domain: "Filetor", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "A folder cannot be copied into itself."])
        }

        var replace = false
        if src.standardizedFileURL.path == dst.standardizedFileURL.path {
            // Same place: a copy becomes a duplicate, a move does nothing.
            if move { control.add(size(of: src)); return }
            dst = uniqueURL(for: dst)
        } else if exists(dst) {
            let choice = await resolve(src: src, dst: dst)
            switch choice {
            case .skip:
                control.add(size(of: src))
                return
            case .stop:
                throw CancellationError()
            case .keepBoth:
                dst = uniqueURL(for: dst)
            case .merge:
                try await merge(src, into: dst)
                return
            case .replace:
                replace = true
            }
        }
        try transferItem(src, to: dst, replace: replace)
    }

    private func merge(_ src: URL, into dst: URL) async throws {
        let children = try fm.contentsOfDirectory(at: src, includingPropertiesForKeys: nil, options: [])
        for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            try await process(child, into: dst)
        }
        if move {
            // Remove the source folder only if everything was moved out of it.
            if (try? fm.contentsOfDirectory(atPath: src.path))?.isEmpty == true {
                try? fm.removeItem(at: src)
            }
        }
    }

    private func transferItem(_ src: URL, to dst: URL, replace: Bool) throws {
        if replace {
            // Copy next to the destination first, then swap, so a failure never loses the old item.
            let tmp = dst.deletingLastPathComponent().appending(path: ".filetor-\(UUID().uuidString)")
            do {
                try doTransfer(src, to: tmp)
            } catch {
                try? fm.removeItem(at: tmp)
                throw error
            }
            do {
                try fm.trashItem(at: dst, resultingItemURL: nil)
                try fm.moveItem(at: tmp, to: dst)
            } catch {
                // No Trash available (for example a network volume): swap in place.
                _ = try fm.replaceItemAt(dst, withItemAt: tmp)
            }
        } else {
            try doTransfer(src, to: dst)
        }
    }

    private func doTransfer(_ src: URL, to dst: URL) throws {
        if move {
            if sameVolume(src, dst.deletingLastPathComponent()) {
                let s = size(of: src)
                try fm.moveItem(at: src, to: dst)
                control.add(s)
            } else {
                try copyTree(src, to: dst)
                try fm.removeItem(at: src)
            }
        } else {
            try copyTree(src, to: dst)
        }
    }

    // MARK: Copying

    private func copyTree(_ src: URL, to dst: URL) throws {
        if control.cancelled { throw CancellationError() }
        let v = try? src.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        if v?.isSymbolicLink == true || v?.isDirectory != true {
            try copyFile(src, to: dst)
            return
        }
        try fm.createDirectory(at: dst, withIntermediateDirectories: false)
        let children = try fm.contentsOfDirectory(at: src, includingPropertiesForKeys: nil, options: [])
        for child in children {
            try copyTree(child, to: dst.appending(path: child.lastPathComponent))
        }
        let meta = copyfile_flags_t(COPYFILE_ACL | COPYFILE_STAT | COPYFILE_XATTR)
        _ = copyfile(src.path, dst.path, nil, meta)
    }

    private func copyFile(_ src: URL, to dst: URL) throws {
        let ctx = CopyContext(control: control)
        let state = copyfile_state_alloc()
        defer { copyfile_state_free(state) }

        let callback: copyfile_callback_t = { what, stage, state, _, _, ctxPtr in
            guard let ctxPtr else { return Int32(COPYFILE_CONTINUE) }
            let c = Unmanaged<CopyContext>.fromOpaque(ctxPtr).takeUnretainedValue()
            if c.control.cancelled { return Int32(COPYFILE_QUIT) }
            if what == Int32(COPYFILE_COPY_DATA), stage == Int32(COPYFILE_PROGRESS), let state {
                var copied: off_t = 0
                copyfile_state_get(state, UInt32(COPYFILE_STATE_COPIED), &copied)
                c.report(Int64(copied))
            }
            return Int32(COPYFILE_CONTINUE)
        }
        copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CB), unsafeBitCast(callback, to: UnsafeRawPointer.self))
        copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CTX), Unmanaged.passUnretained(ctx).toOpaque())

        let flags = copyfile_flags_t(COPYFILE_ACL | COPYFILE_STAT | COPYFILE_XATTR | COPYFILE_DATA
                                     | COPYFILE_NOFOLLOW_SRC | COPYFILE_NOFOLLOW_DST)
        let result = copyfile(src.path, dst.path, state, flags)
        if result != 0 {
            let code = errno
            try? fm.removeItem(at: dst)
            if control.cancelled { throw CancellationError() }
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
        // Make sure bytes of very small files are counted too.
        let final = size(of: src)
        if ctx.last < final { control.add(final - ctx.last) }
    }

    // MARK: Helpers

    private func resolve(src: URL, dst: URL) async -> ConflictChoice {
        let sv = try? src.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
        let dv = try? dst.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
        let srcDir = sv?.isDirectory ?? false
        let dstDir = dv?.isDirectory ?? false
        let canMerge = srcDir && dstDir

        if let s = sticky {
            if s == .merge && !canMerge { return .replace }
            return s
        }
        let info = ConflictInfo(name: src.lastPathComponent,
                                srcIsDir: srcDir, dstIsDir: dstDir,
                                srcSize: Int64(sv?.fileSize ?? 0), dstSize: Int64(dv?.fileSize ?? 0),
                                srcDate: sv?.contentModificationDate, dstDate: dv?.contentModificationDate)
        let answer = await ask(info)
        if answer.applyToAll { sticky = answer.choice }
        return answer.choice
    }

    private func exists(_ url: URL) -> Bool {
        (try? fm.attributesOfItem(atPath: url.path)) != nil
    }

    private func uniqueURL(for url: URL) -> URL {
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

    private func sameVolume(_ a: URL, _ b: URL) -> Bool {
        let va = (try? a.resourceValues(forKeys: [.volumeIdentifierKey]))?.volumeIdentifier as? NSObject
        let vb = (try? b.resourceValues(forKeys: [.volumeIdentifierKey]))?.volumeIdentifier as? NSObject
        guard let va, let vb else { return false }
        return va.isEqual(vb)
    }

    private func size(of url: URL) -> Int64 {
        let v = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])
        if v?.isDirectory == true && v?.isSymbolicLink != true {
            var total: Int64 = 0
            if let e = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) {
                for case let u as URL in e {
                    let r = try? u.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                    if r?.isRegularFile == true { total += Int64(r?.fileSize ?? 0) }
                }
            }
            return total
        }
        return Int64(v?.fileSize ?? 0)
    }
}
