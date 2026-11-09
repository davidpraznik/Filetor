import SwiftUI
import UniformTypeIdentifiers

struct Place: Identifiable, Hashable {
    let name: String
    let icon: String
    let url: URL
    var id: URL { url }
}

struct SidebarView: View {
    let app: AppModel
    @State private var selection: URL?
    @AppStorage("textSize") private var textSize = 1

    private var favorites: [Place] { app.favorites.urls.map { app.favorites.place(for: $0) } }

    @AppStorage("sidebarCollapsed") private var collapsedRaw = ""

    private func isCollapsed(_ title: String) -> Bool { collapsedRaw.split(separator: ",").contains(Substring(title)) }

    private func toggleCollapsed(_ title: String) {
        var set = Set(collapsedRaw.split(separator: ",").map(String.init))
        if set.contains(title) { set.remove(title) } else { set.insert(title) }
        collapsedRaw = set.joined(separator: ",")
    }

    @AppStorage("sidebarOrder") private var orderRaw = "Devices,Cloud,Shared,Favorites"
    @State private var draggingSection: String?
    /// Order while dragging; a plain @State so moves animate (the saved order follows).
    @State private var liveOrder: [String]?
    @State private var draggingFavorite: URL?

    private static let allSections = ["Devices", "Cloud", "Shared", "Favorites"]

    /// Saved section order; unknown names are dropped and missing ones appended.
    private var order: [String] {
        if let liveOrder { return liveOrder }
        var out: [String] = []
        for t in orderRaw.split(separator: ",").map(String.init) where Self.allSections.contains(t) && !out.contains(t) { out.append(t) }
        for t in Self.allSections where !out.contains(t) { out.append(t) }
        return out
    }

    /// Moves a section to the position of `target` (below it when dragged downwards, above it when dragged upwards).
    private func moveSection(_ title: String, onto target: String) {
        var o = order
        guard let from = o.firstIndex(of: title), let to = o.firstIndex(of: target), from != to else { return }
        o.remove(at: from)
        o.insert(title, at: to)
        liveOrder = o
        orderRaw = o.joined(separator: ",")
    }

    /// Clears the drag state once the mouse button is released, also when the drag is cancelled.
    private func watchDragEnd() {
        Task { @MainActor in
            while NSEvent.pressedMouseButtons != 0 { try? await Task.sleep(for: .milliseconds(100)) }
            try? await Task.sleep(for: .milliseconds(150))
            draggingSection = nil
            draggingFavorite = nil
        }
    }

    private func dragCard(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13 * s, weight: .semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 8 * s)
            .frame(width: 200 * s, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(.regularMaterial))
    }

    private func sectionDelegate(_ title: String, urls: Bool = false) -> SectionDropDelegate {
        SectionDropDelegate(
            title: title,
            dragging: $draggingSection,
            draggingFavorite: draggingFavorite,
            acceptsURLs: urls,
            move: { from, to in moveSection(from, onto: to) },
            addURLs: { app.favorites.insert($0, before: nil) }
        )
    }

    @ViewBuilder private func sectionView(_ title: String) -> some View {
        switch title {
        case "Devices":
            section("Devices", devices, ejectable: true)
                .onDrop(of: [.text], delegate: sectionDelegate("Devices"))
        case "Cloud":
            if !cloud.isEmpty {
                section("Cloud", cloud)
                    .onDrop(of: [.text], delegate: sectionDelegate("Cloud"))
            }
        case "Shared":
            shared
                .onDrop(of: [.text], delegate: sectionDelegate("Shared"))
        default:
            section("Favorites", favorites, isFavorites: true)
                .onDrop(of: [.text, .fileURL], delegate: sectionDelegate("Favorites", urls: true))
        }
    }

    @State private var tick = 0

    private var devices: [Place] {
        _ = tick
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeIsInternalKey]
        let vols = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return vols.map { url in
            let v = try? url.resourceValues(forKeys: Set(keys))
            let name = url.path == "/" ? FileManager.default.displayName(atPath: "/") : (v?.volumeName ?? url.lastPathComponent)
            return Place(name: name, icon: (v?.volumeIsInternal ?? true) ? "internaldrive" : "externaldrive", url: url)
        }
    }

    /// iCloud Drive and cloud providers (Google Drive, Dropbox, OneDrive) that exist on this Mac.
    private var cloud: [Place] {
        _ = tick
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        var out: [Place] = []
        let icloud = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs")
        if fm.fileExists(atPath: icloud.path) { out.append(Place(name: "iCloud Drive", icon: "icloud", url: icloud)) }
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
            out.append(Place(name: name, icon: "cloud", url: url))
        }
        return out
    }

    private var s: CGFloat { UIScale.value(textSize) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14 * s) {
                dropStack
                ForEach(order, id: \.self) { title in
                    sectionView(title)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .background(Color.primary.opacity(0.04))
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in tick += 1 }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in tick += 1 }
        .onChange(of: selection) { _, new in
            if let new { app.active.navigate(to: new) }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 11.5 * s, weight: .semibold))
            Image(systemName: isCollapsed(title) ? "chevron.right" : "chevron.down")
                .font(.system(size: 8 * s, weight: .bold))
            Spacer(minLength: 0)
        }
        .foregroundStyle(Color.primary.opacity(0.4))
        .padding(.horizontal, 8)
        .padding(.bottom, 2 * s)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeInOut(duration: 0.15)) { toggleCollapsed(title) } }
        .onDrag {
            draggingSection = title
            watchDragEnd()
            return NSItemProvider(object: title as NSString)
        } preview: {
            dragCard(title)
        }
    }

    private func section(_ title: String, _ places: [Place], ejectable: Bool = false, isFavorites: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2 * s) {
            sectionHeader(title)
            ForEach(isCollapsed(title) ? [] : places) { p in
                let on = selection == p.url
                HStack(spacing: 8 * s) {
                    Image(systemName: p.icon)
                        .font(.system(size: 12.5 * s))
                        .foregroundStyle(Color.filetor)
                        .frame(width: 20 * s)
                    Text(p.name)
                        .font(.system(size: 13 * s))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if ejectable && p.url.path != "/" {
                        Button { app.eject(p.url) } label: {
                            Image(systemName: "eject.fill")
                                .font(.system(size: 10 * s))
                                .foregroundStyle(Color.primary.opacity(0.5))
                        }
                        .buttonStyle(.plain)
                        .help("Eject")
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5 * s)
                .background(RoundedRectangle(cornerRadius: 7).fill(on ? Color.primary.opacity(0.09) : Color.clear))
                .contentShape(Rectangle())
                .onTapGesture { selection = p.url }
                .modifier(FavoriteRowModifier(enabled: isFavorites, url: p.url, app: app, dragging: $draggingFavorite,
                                              card: dragCard(p.name), onDragStart: watchDragEnd))
            }
        }
    }

    @State private var dropTargeted = false

    private var shared: some View {
        VStack(alignment: .leading, spacing: 2 * s) {
            sectionHeader("Shared")
            if !isCollapsed("Shared") {
            HStack(spacing: 8 * s) {
                Image(systemName: "plus")
                    .font(.system(size: 12.5 * s))
                    .foregroundStyle(Color.filetor)
                    .frame(width: 20 * s)
                Text("Connect to Server").font(.system(size: 13 * s))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5 * s)
            .contentShape(Rectangle())
            .onTapGesture { app.showConnect = true }
            ForEach(app.network.servers) { server in
                HStack(spacing: 8 * s) {
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 12.5 * s))
                        .foregroundStyle(Color.filetor)
                        .frame(width: 20 * s)
                    Text(server.name).font(.system(size: 13 * s)).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5 * s)
                .contentShape(Rectangle())
                .help("Connect to \(server.name)")
                .onTapGesture { app.network.connect(server) }
            }
            }
        }
    }

    private var dropStack: some View {
        VStack(alignment: .leading, spacing: 6 * s) {
            Text("Drop Stack")
                .font(.system(size: 11.5 * s, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.4))
                .padding(.horizontal, 8)
            if app.dropStack.isEmpty {
                VStack(spacing: 4 * s) {
                    Image(systemName: "square.3.layers.3d")
                        .font(.system(size: 16 * s, weight: .light))
                    Text("Drag files here to collect them")
                        .font(.system(size: 13 * s))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Color.primary.opacity(0.5))
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12 * s)
            } else {
                VStack(spacing: 0) {
                    DropStackList(urls: app.dropStack, scale: s) { removed in
                        app.dropStack.removeAll { removed.contains($0) }
                    }
                    .frame(height: DropStackList.rowHeight(s) * CGFloat(app.dropStack.count))
                    Button("Clear") { app.dropStack.removeAll() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11.5 * s))
                        .foregroundStyle(Color.primary.opacity(0.5))
                        .padding(.top, 4 * s)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.horizontal, 8)
                }
                .padding(.vertical, 6 * s)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundStyle(dropTargeted ? Color.filetor : Color.primary.opacity(0.3))
                .padding(.top, 20 * s)
        )
        .dropDestination(for: URL.self) { urls, _ in
            for u in urls where !app.dropStack.contains(u) { app.dropStack.append(u) }
            return true
        } isTargeted: { dropTargeted = $0 }
    }
}

/// Drag to reorder (live, with animation), drop folders to add, right-click to remove (Favorites only).
struct FavoriteRowModifier<Card: View>: ViewModifier {
    let enabled: Bool
    let url: URL
    let app: AppModel
    @Binding var dragging: URL?
    let card: Card
    let onDragStart: () -> Void

    func body(content: Content) -> some View {
        if enabled {
            content
                .onDrag {
                    dragging = url
                    onDragStart()
                    return NSItemProvider(object: url as NSURL)
                } preview: {
                    card
                }
                .onDrop(of: [.fileURL], delegate: FavoriteRowDropDelegate(url: url, dragging: $dragging, app: app))
                .contextMenu {
                    Button("Remove from Favorites") { app.favorites.remove(url) }
                }
        } else {
            content
        }
    }
}

/// Reads file URLs from a drop and hands each one over on the main actor.
@MainActor
func loadDroppedURLs(_ info: DropInfo, _ completion: @escaping @MainActor ([URL]) -> Void) {
    for provider in info.itemProviders(for: [.fileURL]) {
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            Task { @MainActor in completion([url]) }
        }
    }
}

/// Dropping on a Favorites row: a favorite being moved slides into place (move cursor, no plus);
/// folders from a file list are added before the row (plus cursor).
struct FavoriteRowDropDelegate: DropDelegate {
    let url: URL
    @Binding var dragging: URL?
    let app: AppModel

    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [.fileURL]) }

    func dropEntered(info: DropInfo) {
        guard let d = dragging, d != url else { return }
        withAnimation(.easeInOut(duration: 0.22)) { app.favorites.move(d, onto: url) }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: dragging != nil ? .move : .copy)
    }

    func performDrop(info: DropInfo) -> Bool {
        if dragging != nil { dragging = nil; return true }
        loadDroppedURLs(info) { [app, url] urls in app.favorites.insert(urls, before: url) }
        return true
    }
}

/// Dropping on a sidebar section: a dragged section slides into place (move cursor);
/// on Favorites, folders from a file list are added at the end.
struct SectionDropDelegate: DropDelegate {
    let title: String
    @Binding var dragging: String?
    let draggingFavorite: URL?
    let acceptsURLs: Bool
    let move: (String, String) -> Void
    let addURLs: @MainActor ([URL]) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        dragging != nil || (acceptsURLs && info.hasItemsConforming(to: [.fileURL]))
    }

    func dropEntered(info: DropInfo) {
        guard let d = dragging, d != title else { return }
        withAnimation(.easeInOut(duration: 0.22)) { move(d, title) }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: (dragging != nil || draggingFavorite != nil) ? .move : .copy)
    }

    func performDrop(info: DropInfo) -> Bool {
        if dragging != nil { dragging = nil; return true }
        if draggingFavorite != nil { return true }
        guard acceptsURLs else { return false }
        loadDroppedURLs(info, addURLs)
        return true
    }
}
