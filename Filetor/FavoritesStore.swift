import SwiftUI
import Observation

/// Sidebar favorites: folders the user keeps, saved between launches.
@Observable
final class FavoritesStore {
    private(set) var urls: [URL]
    private static let key = "favorites.v1"

    init() {
        if let saved = UserDefaults.standard.array(forKey: Self.key) as? [String] {
            urls = saved.map { URL(filePath: $0) }
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            urls = [
                home,
                home.appending(path: "Desktop"),
                home.appending(path: "Documents"),
                home.appending(path: "Downloads"),
                URL(filePath: "/Applications"),
            ]
        }
    }

    private func save() {
        UserDefaults.standard.set(urls.map(\.path), forKey: Self.key)
    }

    /// Adds folders (or moves existing ones) before `target`; with no target they go to the end.
    func insert(_ new: [URL], before target: URL?) {
        for u in new {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir), isDir.boolValue else { continue }
            urls.removeAll { $0 == u }
            if let target, let i = urls.firstIndex(of: target) {
                urls.insert(u, at: i)
            } else {
                urls.append(u)
            }
        }
        save()
    }

    func remove(_ url: URL) {
        urls.removeAll { $0 == url }
        save()
    }

    func contains(_ url: URL) -> Bool { urls.contains(url) }

    func place(for url: URL) -> Place {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch url.path {
        case home.path: return Place(name: "Home", icon: "house", url: url)
        case home.appending(path: "Desktop").path: return Place(name: "Desktop", icon: "menubar.dock.rectangle", url: url)
        case home.appending(path: "Documents").path: return Place(name: "Documents", icon: "doc", url: url)
        case home.appending(path: "Downloads").path: return Place(name: "Downloads", icon: "arrow.down.circle", url: url)
        case "/Applications": return Place(name: "Applications", icon: "square.grid.2x2", url: url)
        default: return Place(name: url.lastPathComponent.isEmpty ? "/" : url.lastPathComponent, icon: "folder", url: url)
        }
    }
}
