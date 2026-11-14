import SwiftUI

/// Clickable path above each pane, Paths style. The + at the right opens a new tab.
struct BreadcrumbBar: View {
    let pane: PaneModel
    let app: AppModel
    let onNewTab: () -> Void
    @AppStorage("textSize") private var textSize = 1
    @State private var contentWidth: CGFloat = 0
    @State private var viewWidth: CGFloat = 0

    private var s: CGFloat { UIScale.value(textSize) }

    /// Shows the end of a long path, or the start when everything fits. Runs again whenever the pane is resized,
    /// so an offset from an earlier, narrower layout never sticks.
    private func align(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            if contentWidth <= viewWidth + 0.5 {
                proxy.scrollTo("start", anchor: .leading)
            } else {
                proxy.scrollTo("end", anchor: .trailing)
            }
        }
    }

    /// Mounted volume (under /Volumes) the pane is in, if any. Its crumbs start at the volume, not at the boot disk.
    private var volumeRoot: URL? {
        let parts = pane.currentURL.standardizedFileURL.pathComponents
        guard parts.count >= 3, parts[1] == "Volumes" else { return nil }
        let v = URL(filePath: "/Volumes/" + parts[2])
        // The boot disk shows up as a symlink in /Volumes; treat it as the normal root.
        if (try? v.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true { return nil }
        return v
    }

    /// Cloud provider folder (iCloud Drive, Google Drive, ...) the pane is in, if any. Its crumbs start at the provider.
    private var cloudRoot: CloudLocation? { CloudLocation.containing(pane.currentURL) }

    private var rootIcon: String {
        if let c = cloudRoot { return c.icon }
        guard let v = volumeRoot else { return "internaldrive" }
        let local = (try? v.resourceValues(forKeys: [.volumeIsLocalKey]))?.volumeIsLocal ?? true
        return local ? "externaldrive" : "externaldrive.connected.to.line.below"
    }

    private var rootName: String {
        if let c = cloudRoot { return c.name }
        return volumeRoot?.lastPathComponent ?? FileManager.default.displayName(atPath: "/")
    }

    private var crumbs: [URL] {
        let base = cloudRoot?.url ?? volumeRoot ?? URL(filePath: "/")
        var list: [URL] = [base]
        var cur = base
        let skip = base.standardizedFileURL.pathComponents.count
        for part in pane.currentURL.standardizedFileURL.pathComponents.dropFirst(skip) {
            cur = cur.appending(path: part)
            list.append(cur)
        }
        return list
    }

    /// Right-click menu of a crumb (folder or disk in the path).
    @ViewBuilder private func crumbMenu(_ url: URL, isRoot: Bool) -> some View {
        let ownGroup = app.groups.first { g in g.tabs.contains { $0 === pane } }
        let otherGroup = app.groups.first { $0 !== ownGroup }
        Button("Open") { pane.navigate(to: url) }
        if app.dual, let otherGroup {
            Button("Open in Other Pane") { otherGroup.current.navigate(to: url) }
        }
        if let ownGroup {
            Button("Open in New Tab") { ownGroup.newTab(at: url) }
        }
        Divider()
        Button("Copy Path") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.path, forType: .string)
        }
        Button("Get Info") { app.getInfo([url]) }
        Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        Button("Open in Terminal") {
            NSWorkspace.shared.open([url],
                                    withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"),
                                    configuration: NSWorkspace.OpenConfiguration())
        }
        Divider()
        Button("Add to Favorites") { app.favorites.insert([url], before: nil) }
        if isRoot, let v = volumeRoot {
            Divider()
            Button("Eject") { app.eject(v) }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                Color.clear.frame(width: 0, height: 1).id("start")
                HStack(spacing: 6 * s) {
                    ForEach(Array(crumbs.enumerated()), id: \.offset) { i, url in
                        if i > 0 {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9 * s, weight: .semibold))
                                .foregroundStyle(Color.primary.opacity(0.35))
                        }
                        Button { pane.navigate(to: url) } label: {
                            HStack(spacing: 5 * s) {
                                if i == 0 {
                                    Image(systemName: rootIcon)
                                        .font(.system(size: 12 * s))
                                        .foregroundStyle(Color.primary.opacity(0.55))
                                } else {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                        .resizable()
                                        .frame(width: 15 * s, height: 15 * s)
                                }
                                Text(i == 0 ? rootName : url.lastPathComponent)
                                    .font(.system(size: 14 * s))
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                        .contextMenu { crumbMenu(url, isRoot: i == 0) }
                        .id(i)
                    }
                }
                .padding(.horizontal, 14)
                Color.clear.frame(width: 0, height: 1).id("end")
                }
                .background(GeometryReader { g in
                    Color.clear.onChange(of: g.size.width, initial: true) { _, w in contentWidth = w; align(proxy) }
                })
            }
            .background(GeometryReader { g in
                Color.clear.onChange(of: g.size.width, initial: true) { _, w in viewWidth = w; align(proxy) }
            })
            // Soft fade at the left edge, so a long path that scrolls under it never ends hard against the border.
            .mask(
                HStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 24 * s)
                    Rectangle()
                }
            )
            .onChange(of: pane.currentURL) { _, _ in align(proxy) }
            }
            Button(action: onNewTab) {
                Image(systemName: "plus")
                    .font(.system(size: 14 * s))
                    .foregroundStyle(Color.primary.opacity(0.55))
                    .frame(width: 36 * s, height: 30 * s)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("New Tab")
        }
        .frame(height: 44 * s)
    }
}


/// iCloud Drive and cloud provider folders with friendly names. One provider with one account is just "Google Drive";
/// with several accounts the account is added, e.g. "Google Drive (name@example.com)".
struct CloudLocation {
    let name: String
    let icon: String
    let url: URL

    static func all() -> [CloudLocation] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var out: [CloudLocation] = []
        let icloud = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        if fm.fileExists(atPath: icloud.path) { out.append(CloudLocation(name: "iCloud Drive", icon: "icloud", url: icloud)) }
        let storage = home.appendingPathComponent("Library/CloudStorage")
        let dirs = (try? fm.contentsOfDirectory(at: storage, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        for url in dirs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let n = url.lastPathComponent
            let (provider, account): (String, String) = {
                if n.hasPrefix("GoogleDrive-") { return ("Google Drive", String(n.dropFirst("GoogleDrive-".count))) }
                if n.hasPrefix("OneDrive-") { return ("OneDrive", String(n.dropFirst("OneDrive-".count))) }
                if n.hasPrefix("Dropbox") { return ("Dropbox", "") }
                return (n, "")
            }()
            let same = dirs.filter { $0.lastPathComponent.hasPrefix(n.split(separator: "-").first.map(String.init) ?? n) }.count
            let name = (same > 1 && !account.isEmpty) ? "\(provider) (\(account))" : provider
            out.append(CloudLocation(name: name, icon: "cloud", url: url))
        }
        return out
    }

    /// The provider folder that contains the given location, if any.
    static func containing(_ location: URL) -> CloudLocation? {
        let path = location.standardizedFileURL.path
        guard path.contains("/Library/CloudStorage/") || path.contains("/Library/Mobile Documents/com~apple~CloudDocs") else { return nil }
        return all().first { path == $0.url.standardizedFileURL.path || path.hasPrefix($0.url.standardizedFileURL.path + "/") }
    }

    /// Title of a folder: the provider name for a cloud provider's own folder, otherwise the folder name.
    static func title(for url: URL) -> String {
        let last = url.lastPathComponent
        guard last.hasPrefix("GoogleDrive-") || last.hasPrefix("OneDrive-") || last.hasPrefix("Dropbox") || last == "com~apple~CloudDocs",
              let c = containing(url), c.url.standardizedFileURL.path == url.standardizedFileURL.path else {
            return (last.isEmpty || last == "/") ? FileManager.default.displayName(atPath: "/") : last
        }
        return c.name
    }
}
