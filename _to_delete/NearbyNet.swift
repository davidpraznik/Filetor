import Foundation
import Darwin

// Send to Mac: same protocol as the Paths app (PATHS1).
// Copies announce themselves with a UDP broadcast (port 47821) and send files over TCP (port 47820).
// The receiver is always asked before anything is written.

nonisolated enum NearbyConst {
    static let magic = "PATHS1"
    static let tcpPort: UInt16 = 47820
    static let udpPort: UInt16 = 47821
}

nonisolated struct NearbyPeer: Identifiable, Hashable, Sendable {
    let id: UInt64
    var name: String
    var ip: UInt32          // network byte order, as in sin_addr.s_addr
    var port: UInt16
    var receiving: Bool
    var seen: Date
}

nonisolated struct NetTransferState: Sendable {
    let id: UInt64
    let label: String
    var done: UInt64 = 0
    var total: UInt64 = 0
    var finished = false
    var error: String?
}

nonisolated final class IncomingRequest: Identifiable, @unchecked Sendable {
    let id: UInt64
    let from: String
    let count: Int
    let bytes: UInt64
    private let semaphore = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var accepted = false
    private var answered = false

    init(id: UInt64, from: String, count: Int, bytes: UInt64) {
        self.id = id; self.from = from; self.count = count; self.bytes = bytes
    }

    func answer(_ accept: Bool) {
        lock.lock()
        if answered { lock.unlock(); return }
        answered = true
        accepted = accept
        lock.unlock()
        semaphore.signal()
    }

    /// Waits for the person to answer. No answer within the time means "no".
    func waitForAnswer(seconds: Int) -> Bool {
        _ = semaphore.wait(timeout: .now() + .seconds(seconds))
        lock.lock(); defer { lock.unlock() }
        return accepted
    }
}

// MARK: - Shared state (touched from several threads, always under the lock)

nonisolated final class NetShared: @unchecked Sendable {
    private let lock = NSLock()
    private var _peers: [UInt64: NearbyPeer] = [:]
    private var _incoming: [IncomingRequest] = []
    private var _transfers: [NetTransferState] = []
    private var _receiving = false
    private var _name = "Mac"
    private var _receiveDir = URL(filePath: NSHomeDirectory()).appending(path: "Downloads")
    private var _listenPort: UInt16 = NearbyConst.tcpPort
    private var _nextId: UInt64 = 0
    var myId: UInt64 = 0

    func newId() -> UInt64 { lock.lock(); defer { lock.unlock() }; _nextId += 1; return _nextId }

    func setIdentity(name: String, receiveDir: URL, receiving: Bool) {
        lock.lock(); _name = name; _receiveDir = receiveDir; _receiving = receiving; lock.unlock()
    }
    var name: String { lock.lock(); defer { lock.unlock() }; return _name.replacingOccurrences(of: "\n", with: " ") }
    var receiveDir: URL { lock.lock(); defer { lock.unlock() }; return _receiveDir }
    var receiving: Bool { lock.lock(); defer { lock.unlock() }; return _receiving }
    var listenPort: UInt16 {
        get { lock.lock(); defer { lock.unlock() }; return _listenPort }
        set { lock.lock(); _listenPort = newValue; lock.unlock() }
    }

    func upsert(_ peer: NearbyPeer) { lock.lock(); _peers[peer.id] = peer; lock.unlock() }
    func peers() -> [NearbyPeer] {
        lock.lock(); defer { lock.unlock() }
        let cutoff = Date().addingTimeInterval(-9)
        _peers = _peers.filter { $0.value.seen > cutoff }
        return _peers.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func addIncoming(_ r: IncomingRequest) { lock.lock(); _incoming.append(r); lock.unlock() }
    func removeIncoming(_ id: UInt64) { lock.lock(); _incoming.removeAll { $0.id == id }; lock.unlock() }
    func firstIncoming() -> IncomingRequest? { lock.lock(); defer { lock.unlock() }; return _incoming.first }

    func addTransfer(_ t: NetTransferState) { lock.lock(); _transfers.append(t); lock.unlock() }
    func update(_ id: UInt64, _ f: (inout NetTransferState) -> Void) {
        lock.lock()
        if let i = _transfers.firstIndex(where: { $0.id == id }) { f(&_transfers[i]) }
        lock.unlock()
    }
    func transfers() -> [NetTransferState] { lock.lock(); defer { lock.unlock() }; return _transfers }
    func removeTransfer(_ id: UInt64) { lock.lock(); _transfers.removeAll { $0.id == id }; lock.unlock() }
}

// MARK: - Socket helpers

nonisolated enum Sock {
    static func addr(ip: UInt32, port: UInt16) -> sockaddr_in {
        var a = sockaddr_in()
        a.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        a.sin_family = sa_family_t(AF_INET)
        a.sin_port = port.bigEndian
        a.sin_addr = in_addr(s_addr: ip)
        return a
    }

    static func bindTo(_ fd: Int32, _ a: sockaddr_in) -> Bool {
        var a = a
        return withUnsafePointer(to: &a) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }

    static func connectTo(_ fd: Int32, _ a: sockaddr_in) -> Bool {
        var a = a
        return withUnsafePointer(to: &a) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
            }
        }
    }

    static func setOpt(_ fd: Int32, _ name: Int32, _ value: Int32 = 1) {
        var v = value
        setsockopt(fd, SOL_SOCKET, name, &v, socklen_t(MemoryLayout<Int32>.size))
    }

    static func setTimeout(_ fd: Int32, _ which: Int32, seconds: Int) {
        var tv = timeval(tv_sec: seconds, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, which, &tv, socklen_t(MemoryLayout<timeval>.size))
    }

    static func localPort(_ fd: Int32) -> UInt16 {
        var a = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        withUnsafeMutablePointer(to: &a) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { _ = getsockname(fd, $0, &len) }
        }
        return UInt16(bigEndian: a.sin_port)
    }

    static func writeAll(_ fd: Int32, _ bytes: [UInt8]) -> Bool {
        var off = 0
        while off < bytes.count {
            let n = bytes[off...].withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
            if n <= 0 { return false }
            off += n
        }
        return true
    }

    static func writeLine(_ fd: Int32, _ s: String) -> Bool { writeAll(fd, Array((s + "\n").utf8)) }
}

/// Buffered line and byte reader on a socket.
nonisolated final class FDReader {
    let fd: Int32
    private var buf: [UInt8] = []
    private var start = 0

    init(_ fd: Int32) { self.fd = fd }

    private func fill() -> Bool {
        let cap = 64 * 1024
        var tmp = [UInt8](repeating: 0, count: cap)
        let n = read(fd, &tmp, cap)
        if n <= 0 { return false }
        if start > 0 { buf.removeFirst(start); start = 0 }
        buf.append(contentsOf: tmp[0..<n])
        return true
    }

    func readLine() -> String? {
        while true {
            if let i = buf[start...].firstIndex(of: 10) {
                let line = String(decoding: buf[start..<i], as: UTF8.self)
                start = i + 1
                return line
            }
            if !fill() { return nil }
        }
    }

    /// Reads up to `max` bytes (at least one unless the connection ended).
    func readSome(max: Int) -> [UInt8]? {
        if start >= buf.count, !fill() { return nil }
        let end = Swift.min(buf.count, start + max)
        let chunk = Array(buf[start..<end])
        start = end
        return chunk
    }
}

// MARK: - Service

nonisolated final class NearbyService: @unchecked Sendable {
    let shared = NetShared()
    private var started = false
    var startError: String?

    func start() {
        guard !started else { return }
        started = true
        shared.myId = UInt64(ProcessInfo.processInfo.processIdentifier) ^ UInt64(Date().timeIntervalSince1970 * 1000)

        // TCP listener
        var fd = socket(AF_INET, SOCK_STREAM, 0)
        Sock.setOpt(fd, SO_REUSEADDR)
        Sock.setOpt(fd, SO_NOSIGPIPE)
        if !Sock.bindTo(fd, Sock.addr(ip: 0, port: NearbyConst.tcpPort)) {
            close(fd)
            fd = socket(AF_INET, SOCK_STREAM, 0)
            Sock.setOpt(fd, SO_NOSIGPIPE)
            _ = Sock.bindTo(fd, Sock.addr(ip: 0, port: 0))
        }
        if listen(fd, 8) == 0 {
            shared.listenPort = Sock.localPort(fd)
            let shared = self.shared
            let listenFD = fd
            DispatchQueue.global(qos: .utility).async {
                while true {
                    let conn = accept(listenFD, nil, nil)
                    if conn < 0 { continue }
                    Sock.setOpt(conn, SO_NOSIGPIPE)
                    DispatchQueue.global(qos: .userInitiated).async {
                        NearbyService.receive(shared, conn)
                    }
                }
            }
        } else {
            startError = "Can't listen for files."
        }

        // UDP discovery
        let udp = socket(AF_INET, SOCK_DGRAM, 0)
        Sock.setOpt(udp, SO_REUSEADDR)
        Sock.setOpt(udp, SO_REUSEPORT)
        Sock.setOpt(udp, SO_BROADCAST)
        Sock.setTimeout(udp, SO_RCVTIMEO, seconds: 1)
        if Sock.bindTo(udp, Sock.addr(ip: 0, port: NearbyConst.udpPort)) {
            let shared = self.shared
            DispatchQueue.global(qos: .utility).async { NearbyService.announceLoop(shared, udp) }
            DispatchQueue.global(qos: .utility).async { NearbyService.listenLoop(shared, udp) }
        } else {
            startError = "Can't look for nearby Macs."
        }
    }

    // MARK: Discovery

    private static func announceLoop(_ shared: NetShared, _ fd: Int32) {
        while true {
            let recv = shared.receiving ? 1 : 0
            let msg = "\(NearbyConst.magic) HELLO \(shared.myId) \(shared.listenPort) \(recv) \(shared.name)"
            var dest = Sock.addr(ip: 0xFFFF_FFFF, port: NearbyConst.udpPort)
            let bytes = Array(msg.utf8)
            _ = withUnsafePointer(to: &dest) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(fd, bytes, bytes.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            Thread.sleep(forTimeInterval: 2)
        }
    }

    private static func listenLoop(_ shared: NetShared, _ fd: Int32) {
        let cap = 512
        var buf = [UInt8](repeating: 0, count: cap)
        while true {
            var from = sockaddr_in()
            var len = socklen_t(MemoryLayout<sockaddr_in>.size)
            let n = withUnsafeMutablePointer(to: &from) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    recvfrom(fd, &buf, cap, 0, $0, &len)
                }
            }
            if n <= 0 { continue }
            let text = String(decoding: buf[0..<n], as: UTF8.self)
            let parts = text.split(separator: " ", maxSplits: 5, omittingEmptySubsequences: false)
            guard parts.count == 6, parts[0] == NearbyConst.magic, parts[1] == "HELLO",
                  let id = UInt64(parts[2]), let port = UInt16(parts[3]) else { continue }
            if id == shared.myId { continue }
            shared.upsert(NearbyPeer(id: id, name: String(parts[5]), ip: from.sin_addr.s_addr,
                                     port: port, receiving: parts[4] == "1", seen: Date()))
        }
    }

    // MARK: Sending

    private enum Item {
        case dir(String)
        case file(String, URL, UInt64)
    }

    private static func collect(_ urls: [URL]) throws -> [Item] {
        var out: [Item] = []
        func walk(_ url: URL, _ rel: String) throws {
            let v = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            if v.isDirectory == true {
                out.append(.dir(rel))
                let kids = try FileManager.default.contentsOfDirectory(atPath: url.path).sorted()
                for k in kids { try walk(url.appending(path: k), rel + "/" + k) }
            } else {
                out.append(.file(rel, url, UInt64(v.fileSize ?? 0)))
            }
        }
        for u in urls { try walk(u, u.lastPathComponent) }
        return out
    }

    func send(to peer: NearbyPeer, urls: [URL]) {
        let shared = self.shared
        let id = shared.newId()
        let label = urls.count == 1 ? "\(urls[0].lastPathComponent) → \(peer.name)" : "\(urls.count) items → \(peer.name)"
        shared.addTransfer(NetTransferState(id: id, label: label))
        DispatchQueue.global(qos: .userInitiated).async {
            let result = NearbyService.sendNow(shared, id, peer, urls)
            shared.update(id) { t in
                t.finished = true
                if case .failure(let e) = result { t.error = e.message }
            }
        }
    }

    private struct NetError: Error { let message: String }

    private static func sendNow(_ shared: NetShared, _ id: UInt64, _ peer: NearbyPeer, _ urls: [URL]) -> Result<Void, NetError> {
        let list: [Item]
        do { list = try collect(urls) } catch { return .failure(NetError(message: "Couldn't read the files: \(error.localizedDescription)")) }
        let total = list.reduce(UInt64(0)) { if case .file(_, _, let s) = $1 { return $0 + s } else { return $0 } }
        shared.update(id) { $0.total = total }

        let fd = socket(AF_INET, SOCK_STREAM, 0)
        defer { close(fd) }
        Sock.setOpt(fd, SO_NOSIGPIPE)
        Sock.setTimeout(fd, SO_SNDTIMEO, seconds: 5)
        guard Sock.connectTo(fd, Sock.addr(ip: peer.ip, port: peer.port)) else {
            return .failure(NetError(message: "Couldn't reach \(peer.name)."))
        }
        Sock.setTimeout(fd, SO_SNDTIMEO, seconds: 60)
        Sock.setTimeout(fd, SO_RCVTIMEO, seconds: 180)   // the other person has a couple of minutes to answer

        let reader = FDReader(fd)
        let header = "\(NearbyConst.magic)\n\(shared.name)\n\(urls.count)\n\(total)\n"
        guard Sock.writeAll(fd, Array(header.utf8)) else { return .failure(NetError(message: "Connection lost.")) }
        guard let reply = reader.readLine() else { return .failure(NetError(message: "No answer.")) }
        guard reply.trimmingCharacters(in: .whitespaces) == "OK" else {
            return .failure(NetError(message: "\(peer.name) declined, or isn't accepting files right now."))
        }

        var done: UInt64 = 0
        for item in list {
            switch item {
            case .dir(let rel):
                if !Sock.writeLine(fd, "D \(rel)") { return .failure(NetError(message: "Connection lost.")) }
            case .file(let rel, let url, let size):
                if !Sock.writeLine(fd, "F \(size) \(rel)") { return .failure(NetError(message: "Connection lost.")) }
                guard let h = try? FileHandle(forReadingFrom: url) else {
                    return .failure(NetError(message: "Couldn't open \(rel)."))
                }
                defer { try? h.close() }
                var left = size
                while left > 0 {
                    let chunk = Int(min(left, 256 * 1024))
                    guard let data = try? h.read(upToCount: chunk), !data.isEmpty else {
                        return .failure(NetError(message: "\(rel) changed while sending."))
                    }
                    if !Sock.writeAll(fd, [UInt8](data)) { return .failure(NetError(message: "Connection lost.")) }
                    left -= UInt64(data.count)
                    done += UInt64(data.count)
                    shared.update(id) { $0.done = done }
                }
            }
        }
        _ = Sock.writeLine(fd, "END")
        _ = reader.readLine()
        return .success(())
    }

    // MARK: Receiving

    /// Only plain relative paths are accepted from the network.
    private static func safeRelative(_ rel: String) -> [String]? {
        guard !rel.isEmpty, !rel.hasPrefix("/") else { return nil }
        let comps = rel.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        for c in comps where c.isEmpty || c == "." || c == ".." { return nil }
        return comps
    }

    private static func uniqueName(in dir: URL, _ name: String) -> String {
        let fm = FileManager.default
        var candidate = name
        var n = 2
        let ns = name as NSString
        let ext = ns.pathExtension
        let base = ext.isEmpty ? name : ns.deletingPathExtension
        while fm.fileExists(atPath: dir.appending(path: candidate).path) {
            candidate = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            n += 1
        }
        return candidate
    }

    private static func receive(_ shared: NetShared, _ fd: Int32) {
        defer { close(fd) }
        Sock.setTimeout(fd, SO_RCVTIMEO, seconds: 60)
        let r = FDReader(fd)
        guard r.readLine() == NearbyConst.magic,
              let from = r.readLine(),
              let count = r.readLine().flatMap({ Int($0) }),
              let bytes = r.readLine().flatMap({ UInt64($0) }) else { return }

        guard shared.receiving else { _ = Sock.writeLine(fd, "NO"); return }

        let req = IncomingRequest(id: shared.newId(), from: from, count: count, bytes: bytes)
        shared.addIncoming(req)
        let accepted = req.waitForAnswer(seconds: 170)
        shared.removeIncoming(req.id)
        guard accepted else { _ = Sock.writeLine(fd, "NO"); return }
        _ = Sock.writeLine(fd, "OK")

        let dir = shared.receiveDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let id = shared.newId()
        shared.addTransfer(NetTransferState(id: id, label: "From \(from)", total: bytes))

        var tops: [String: String] = [:]
        func target(_ comps: [String]) -> URL {
            let top = comps[0]
            let mapped = tops[top] ?? { let u = uniqueName(in: dir, top); tops[top] = u; return u }()
            var url = dir.appending(path: mapped)
            for c in comps.dropFirst() { url = url.appending(path: c) }
            return url
        }

        var failure: String?
        var done: UInt64 = 0
        loop: while true {
            guard let line = r.readLine() else { failure = "Connection closed early."; break }
            if line == "END" || line.isEmpty { break }
            if line.hasPrefix("D ") {
                guard let comps = safeRelative(String(line.dropFirst(2))) else { failure = "Bad path."; break }
                try? FileManager.default.createDirectory(at: target(comps), withIntermediateDirectories: true)
            } else if line.hasPrefix("F ") {
                let rest = line.dropFirst(2)
                guard let space = rest.firstIndex(of: " "), let size = UInt64(rest[rest.startIndex..<space]),
                      let comps = safeRelative(String(rest[rest.index(after: space)...])) else { failure = "Bad header."; break }
                let url = target(comps)
                try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                FileManager.default.createFile(atPath: url.path, contents: nil)
                guard let h = try? FileHandle(forWritingTo: url) else { failure = "Couldn't write \(url.lastPathComponent)."; break }
                var left = size
                while left > 0 {
                    guard let chunk = r.readSome(max: Int(min(left, 256 * 1024))) else {
                        failure = "Connection closed early."
                        try? h.close()
                        break loop
                    }
                    try? h.write(contentsOf: chunk)
                    left -= UInt64(chunk.count)
                    done += UInt64(chunk.count)
                    shared.update(id) { $0.done = done }
                }
                try? h.close()
            } else {
                failure = "Unexpected data."
                break
            }
        }
        _ = Sock.writeLine(fd, "DONE")
        shared.update(id) { t in
            t.finished = true
            t.error = failure
        }
    }
}
