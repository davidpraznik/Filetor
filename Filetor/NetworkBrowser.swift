import Foundation
import Observation
import AppKit
import NetFS

struct NetworkServer: Identifiable, Hashable {
    let name: String
    let type: String     // "_smb._tcp." or "_afp._tcp."
    var id: String { name }
}

/// Finds file servers on the local network (Bonjour) so they can be listed under Shared and mounted with a click.
@Observable
final class NetworkBrowser: NSObject, NetServiceBrowserDelegate, NetServiceDelegate {
    var servers: [NetworkServer] = []
    var onError: ((String) -> Void)?
    var onMounted: ((URL) -> Void)?
    @ObservationIgnored private let ownName = Host.current().localizedName ?? ProcessInfo.processInfo.hostName

    @ObservationIgnored private var browsers: [NetServiceBrowser] = []
    @ObservationIgnored private var resolving: [NetService] = []

    func start() {
        guard browsers.isEmpty else { return }
        for type in ["_smb._tcp.", "_afp._tcp."] {
            let b = NetServiceBrowser()
            b.delegate = self
            b.searchForServices(ofType: type, inDomain: "local.")
            browsers.append(b)
        }
    }

    /// Resolves the host name of the server, then macOS mounts it (and asks for the login).
    func connect(_ server: NetworkServer) {
        let svc = NetService(domain: "local.", type: server.type, name: server.name)
        svc.delegate = self
        resolving.append(svc)
        svc.resolve(withTimeout: 6)
    }

    /// Mounts the share without opening a Finder window; macOS asks for the login itself.
    private func mount(_ url: URL, name: String) {
        Task.detached {
            let opts = NSMutableDictionary()
            opts["UIOption"] = "AllowUI"
            var points: Unmanaged<CFArray>?
            let rc = NetFSMountURLSync(url as CFURL, nil, nil, nil, opts, nil, &points)
            let paths = (points?.takeRetainedValue() as? [String]) ?? []
            await MainActor.run {
                if let first = paths.first {
                    self.onMounted?(URL(filePath: first))
                } else if rc != 0 && rc != -128 && rc != 17 {
                    self.onError?("Couldn't connect to \(name) (error \(rc)).")
                }
            }
        }
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
