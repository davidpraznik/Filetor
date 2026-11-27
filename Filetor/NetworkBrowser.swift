import Foundation
import SwiftUI
import Observation
import AppKit
import NetFS
import Network
import Darwin

struct NetworkServer: Identifiable, Hashable {
    let name: String
    let type: String     // "_smb._tcp." or "_afp._tcp."
    /// Set for servers found by the address scan (they do not announce themselves with Bonjour).
    var host: String? = nil
    var id: String { name }
}

/// Finds file servers on the local network (Bonjour) so they can be listed under Shared and mounted with a click.
@Observable
final class NetworkBrowser: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    var servers: [NetworkServer] = []
    /// Name of the server that is being mounted right now (nil when no connection is in progress).
    var connecting: String?
    /// The first search of the network has finished.
    var searched = false
    var onError: ((String) -> Void)?
    var onMounted: ((URL) -> Void)?
    @ObservationIgnored private let ownName = Host.current().localizedName ?? ProcessInfo.processInfo.hostName

    @ObservationIgnored private var browsers: [NetServiceBrowser] = []
    @ObservationIgnored private var resolving: [NetService] = []
    @ObservationIgnored private var scanTask: Task<Void, Never>?

    var isEnabled: Bool { UserDefaults.standard.object(forKey: "networkSearch") as? Bool ?? true }

    /// Turns the search on or off (Settings > General > Network).
    func setEnabled(_ on: Bool) {
        if on {
            start()
        } else {
            scanTask?.cancel()
            scanTask = nil
            browsers.forEach { $0.stop() }
            browsers.removeAll()
            servers.removeAll()
            searched = false
        }
    }

    func start() {
        guard isEnabled, browsers.isEmpty else { return }
        for type in ["_smb._tcp.", "_afp._tcp."] {
            let b = NetServiceBrowser()
            b.delegate = self
            b.searchForServices(ofType: type, inDomain: "local.")
            browsers.append(b)
        }
        startScanning()
    }

    /// Resolves the host name of the server, then macOS mounts it (and asks for the login).
    func connect(_ server: NetworkServer) {
        if let host = server.host, let url = URL(string: "smb://\(host)") {
            mount(url, name: server.name)
            return
        }
        let svc = NetService(domain: "local.", type: server.type, name: server.name)
        svc.delegate = self
        resolving.append(svc)
        svc.resolve(withTimeout: 6)
    }

    /// Connects to an address typed by the user (a server that does not announce itself on the network).
    func connect(address: URL) {
        let name = address.host ?? address.absoluteString
        mount(address, name: name)
    }

    /// Mounts the share without opening a Finder window; macOS asks for the login itself.
    private func mount(_ url: URL, name: String) {
        connecting = name
        Task.detached {
            let opts = NSMutableDictionary()
            opts["UIOption"] = "AllowUI"
            var points: Unmanaged<CFArray>?
            let rc = NetFSMountURLSync(url as CFURL, nil, nil, nil, opts, nil, &points)
            let paths = (points?.takeRetainedValue() as? [String]) ?? []
            await MainActor.run {
                self.connecting = nil
                if let first = paths.first {
                    self.onMounted?(URL(filePath: first))
                } else if rc != 0 && rc != -128 && rc != 17 {
                    self.onError?("Couldn't connect to \(name) (error \(rc)).")
                }
            }
        }
    }


    // MARK: Address scan (servers that do not announce themselves)

    /// Looks for file servers (TCP port 445) in the local subnet, now and every two minutes.
    private func startScanning() {
        guard scanTask == nil else { return }
        scanTask = Task { [weak self] in
            while !Task.isCancelled {
                let found = await Task.detached(priority: .utility) { await NetworkBrowser.scanSubnets() }.value
                guard let self else { return }
                self.applyScan(found)
                try? await Task.sleep(for: .seconds(120))
            }
        }
    }

    private func applyScan(_ found: [NetworkServer]) {
        let announced = servers.filter { $0.host == nil }
        var result = announced
        for s in found {
            let key = s.name.lowercased()
            if announced.contains(where: { key.hasPrefix($0.name.lowercased()) || $0.name.lowercased().hasPrefix(key) }) { continue }
            result.append(s)
        }
        result.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        if result != servers { servers = result }
        searched = true
    }

    nonisolated private final class OneShot: @unchecked Sendable {
        private let lock = NSLock()
        private var fired = false
        func fire() -> Bool {
            lock.lock(); defer { lock.unlock() }
            if fired { return false }
            fired = true
            return true
        }
    }

    nonisolated private static func ipString(_ ip: UInt32) -> String {
        "\(ip >> 24).\((ip >> 16) & 255).\((ip >> 8) & 255).\(ip & 255)"
    }

    /// The local IPv4 addresses and the host addresses to check (the subnet of each active interface, at most a /24).
    nonisolated private static func localHosts() -> (own: Set<UInt32>, hosts: [UInt32]) {
        var own = Set<UInt32>()
        var hosts: [UInt32] = []
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return (own, hosts) }
        defer { freeifaddrs(list) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let ifa = cursor {
            defer { cursor = ifa.pointee.ifa_next }
            let flags = Int32(ifa.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0,
                  let addr = ifa.pointee.ifa_addr, addr.pointee.sa_family == sa_family_t(AF_INET),
                  let maskPtr = ifa.pointee.ifa_netmask else { continue }
            let ip = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            let mask = maskPtr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            let a = ip >> 24, b = (ip >> 16) & 255
            let isPrivate = a == 10 || (a == 172 && (16...31).contains(b)) || (a == 192 && b == 168)
            own.insert(ip)
            guard isPrivate else { continue }
            let useMask = mask < 0xFFFFFF00 ? 0xFFFFFF00 : mask
            let network = ip & useMask
            let count = ~useMask &+ 1
            guard count >= 4 else { continue }
            for offset in 1..<(count - 1) {
                let host = network + offset
                if host != ip, !hosts.contains(host) { hosts.append(host) }
            }
        }
        return (own, hosts)
    }

    nonisolated private static func probe(_ ip: UInt32) async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            let conn = NWConnection(host: NWEndpoint.Host(ipString(ip)), port: 445, using: .tcp)
            let once = OneShot()
            let finish: @Sendable (Bool) -> Void = { ok in
                if once.fire() {
                    conn.cancel()
                    cont.resume(returning: ok)
                }
            }
            conn.stateUpdateHandler = { state in
                switch state {
                case .ready: finish(true)
                case .failed, .cancelled: finish(false)
                default: break
                }
            }
            conn.start(queue: .global(qos: .utility))
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.2) { finish(false) }
        }
    }

    /// The computer's name from reverse DNS (what the router knows it as), first part only.
    nonisolated private static func hostName(_ ip: UInt32) -> String? {
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = in_addr_t(ip.bigEndian)
        var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getnameinfo($0, socklen_t(MemoryLayout<sockaddr_in>.size), &buffer, socklen_t(buffer.count), nil, 0, NI_NAMEREQD)
            }
        }
        guard rc == 0 else { return nil }
        let name = String(cString: buffer).split(separator: ".").first.map(String.init) ?? ""
        return name.isEmpty ? nil : name
    }

    nonisolated private static func scanSubnets() async -> [NetworkServer] {
        let local = localHosts()
        guard !local.hosts.isEmpty else { return [] }
        var hits: [UInt32] = []
        await withTaskGroup(of: (UInt32, Bool).self) { group in
            var iterator = local.hosts.makeIterator()
            var running = 0
            while running < 64, let ip = iterator.next() {
                group.addTask { (ip, await probe(ip)) }
                running += 1
            }
            for await (ip, ok) in group {
                if ok { hits.append(ip) }
                if let next = iterator.next() { group.addTask { (next, await probe(next)) } }
            }
        }
        var found: [NetworkServer] = []
        for ip in hits.sorted() where !local.own.contains(ip) {
            let address = ipString(ip)
            found.append(NetworkServer(name: hostName(ip) ?? address, type: "_smb._tcp.", host: address))
        }
        return found
    }

    // MARK: Browser delegate

    nonisolated func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        let item = NetworkServer(name: service.name, type: service.type)
        Task { @MainActor in
            if item.name == self.ownName { return }
            // One entry per computer; smb wins over afp.
            if let i = self.servers.firstIndex(where: { $0.name == item.name }) {
                if self.servers[i].type.hasPrefix("_afp"), item.type.hasPrefix("_smb") { self.servers[i] = item }
            } else {
                // A computer found by the scan earlier is now announced by name; keep only the announced one.
                self.servers.removeAll { $0.host != nil && $0.name.lowercased().hasPrefix(item.name.lowercased()) }
                self.servers.append(item)
                self.servers.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            }
        }
    }

    nonisolated func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        let name = service.name
        let type = service.type
        Task { @MainActor in
            self.servers.removeAll { $0.name == name && $0.type == type }
        }
    }

    // MARK: Resolve delegate

    nonisolated func netServiceDidResolveAddress(_ sender: NetService) {
        let host = (sender.hostName ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let scheme = sender.type.hasPrefix("_afp") ? "afp" : "smb"
        let name = sender.name
        let key = ObjectIdentifier(sender)
        Task { @MainActor in
            self.resolving.removeAll { ObjectIdentifier($0) == key }
            if let url = URL(string: "\(scheme)://\(host)") {
                self.mount(url, name: name)
            }
        }
    }

    nonisolated func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        let name = sender.name
        let key = ObjectIdentifier(sender)
        Task { @MainActor in
            self.resolving.removeAll { ObjectIdentifier($0) == key }
            self.onError?("Couldn't reach \(name).")
        }
    }
}

/// The list of file servers found on the network, shown in a pane (sidebar > Shared > Network).
struct NetworkListView: View {
    let app: AppModel
    let scale: CGFloat
    @AppStorage("networkSearch") private var networkSearch = true
    @State private var selected: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "globe").foregroundStyle(Color.filetor)
                Text("Network").font(.system(size: 13 * scale, weight: .medium))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8 * scale)
            Divider()
            if app.network.servers.isEmpty {
                VStack(spacing: 8) {
                    if !networkSearch {
                        Text("Network search is off. Turn it on in Settings > General.")
                    } else if app.network.searched {
                        Text("No servers found. Use Connect to Server to enter an address.")
                    } else {
                        ProgressView().controlSize(.small)
                        Text("Searching the network…")
                    }
                }
                .font(.system(size: 13 * scale))
                .foregroundStyle(Color.primary.opacity(0.55))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(app.network.servers) { server in
                            HStack(spacing: 10) {
                                Image(systemName: "desktopcomputer")
                                    .font(.system(size: 14 * scale))
                                    .foregroundStyle(Color.filetor)
                                    .frame(width: 22 * scale)
                                Text(server.name).font(.system(size: 13 * scale)).lineLimit(1)
                                Spacer(minLength: 8)
                                Text("Server")
                                    .font(.system(size: 13 * scale))
                                    .foregroundStyle(Color.primary.opacity(0.55))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6 * scale)
                            .background(selected == server.id ? Color.filetor.opacity(0.18) : Color.clear)
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { app.network.connect(server) }
                            .onTapGesture { selected = server.id }
                            .help("Double-click to connect to \(server.name)")
                        }
                    }
                }
            }
        }
    }
}
