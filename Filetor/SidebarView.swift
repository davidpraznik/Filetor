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
    @AppStorage("textSize") private var textSize = 1
    @AppStorage("themedFolders") private var themedFolders = false
    @AppStorage("folderColor") private var folderColor = "multi"

    private var favorites: [Place] { app.favorites.urls.map { app.favorites.place(for: $0) } }

    @AppStorage("sidebarCollapsed") private var collapsedRaw = ""

    private func isCollapsed(_ title: String) -> Bool { collapsedRaw.split(separator: ",").contains(Substring(title)) }

    private func toggleCollapsed(_ title: String) {
        var set = Set(collapsedRaw.split(separator: ",").map(String.init))
        if set.contains(title) { set.remove(title) } else { set.insert(title) }
        collapsedRaw = set.joined(separator: ",")
    }

    @AppStorage("sidebarOrder") private var orderRaw = "Favorites,Locations,Searches,Tags"
    @AppStorage("hiddenSidebarSections") private var hiddenRaw = ""
    @State private var draggingSection: String?
    /// Order while dragging; a plain @State so moves animate (the saved order follows).
    @State private var liveOrder: [String]?
    @State private var draggingFavorite: URL?
    @State private var hoveredHeader: String?

    /// Sections that can be dragged; Locations holds Cloud, Disks and Network.
    private static let allSections = ["Favorites", "Locations", "Searches", "Tags"]
    /// Entry types that can be shown or hidden (Settings > Window and the right-click menu).
    private static let hideable: [(id: String, title: String)] = [
        ("Favorites", "Favorites"), ("Cloud", "Cloud Storage"), ("Disks", "Disks"),
        ("Network", "Network"), ("Searches", "Searches"), ("Tags", "Tags")]
    private var locationsVisible: Bool {
        ["Cloud", "Disks", "Network"].contains { !hiddenSections.contains($0) }
    }

    private var hiddenSections: Set<String> { Set(hiddenRaw.split(separator: ",").map(String.init)) }

    private func setHidden(_ title: String, _ hidden: Bool) {
        var set = hiddenSections
        if hidden { set.insert(title) } else { set.remove(title) }
        hiddenRaw = set.sorted().joined(separator: ",")
    }

    /// Right-click anywhere in the sidebar: tick the sections to show.
    @ViewBuilder private var sectionsMenu: some View {
        ForEach(Self.hideable, id: \.id) { item in
            Toggle(item.title, isOn: Binding(
                get: { !hiddenSections.contains(item.id) },
                set: { setHidden(item.id, !$0) }))
        }
        Divider()
        Button("Sidebar Settings…") {
            app.settingsPage = SettingsPage.window
            app.showSettings = true
        }
    }

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
            draggingLocation = nil
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
            favorites: app.favorites
        )
    }

    @ViewBuilder private func sectionView(_ title: String) -> some View {
        switch title {
        case "Locations":
            if locationsVisible {
                locationsSection
                    .onDrop(of: [.text], delegate: sectionDelegate("Locations"))
            }
        case "Searches":
            if !hiddenSections.contains("Searches") {
                searchesSection
                    .onDrop(of: [.text], delegate: sectionDelegate("Searches"))
            }
        case "Tags":
            if !hiddenSections.contains("Tags") {
                tagsSection
                    .onDrop(of: [.text], delegate: sectionDelegate("Tags"))
            }
        default:
            if !hiddenSections.contains("Favorites") {
                section("Favorites", favorites, isFavorites: true)
                    .onDrop(of: [.text, .fileURL], delegate: sectionDelegate("Favorites", urls: true))
            }
        }
    }

    /// One row of the Locations section: a cloud provider, a disk or Network.
    private struct LocationEntry: Identifiable {
        let id: String
        let place: Place?      // nil = Network
        let ejectable: Bool
    }

    @AppStorage("locationsOrder") private var locOrderRaw = ""
    @State private var draggingLocation: String?
    /// Order while dragging; a plain @State so the moves animate like the Favorites (the saved order follows).
    @State private var liveLocOrder: [String]?

    /// Default order (cloud, disks, Network) with the saved manual order applied on top.
    private var locationEntries: [LocationEntry] {
        var all: [LocationEntry] = []
        if !hiddenSections.contains("Cloud") {
            all += cloud.map { LocationEntry(id: "cloud:" + $0.url.path, place: $0, ejectable: false) }
        }
        if !hiddenSections.contains("Disks") {
            all += devices.map { LocationEntry(id: "disk:" + $0.url.path, place: $0, ejectable: $0.url.path != "/") }
        }
        if !hiddenSections.contains("Network") {
            all.append(LocationEntry(id: "network", place: nil, ejectable: false))
        }
        let saved = liveLocOrder ?? locOrderRaw.split(separator: "\n").map(String.init)
        var out: [LocationEntry] = []
        for id in saved { if let e = all.first(where: { $0.id == id }), !out.contains(where: { $0.id == id }) { out.append(e) } }
        for e in all where !out.contains(where: { $0.id == e.id }) { out.append(e) }
        return out
    }

    private func moveLocation(_ id: String, onto target: String) {
        var ids = locationEntries.map(\.id)
        guard let from = ids.firstIndex(of: id), let to = ids.firstIndex(of: target), from != to else { return }
        ids.remove(at: from)
        ids.insert(id, at: to)
        liveLocOrder = ids
        locOrderRaw = ids.joined(separator: "\n")
    }

    /// Cloud storage, disks (with eject) and Network in one section, like Finder; rows can be dragged into any order.
    private var locationsSection: some View {
        VStack(alignment: .leading, spacing: 2 * s) {
            sectionHeader("Locations")
            ForEach(isCollapsed("Locations") ? [] : locationEntries) { e in
                locationRow(e)
            }
        }
    }

    @ViewBuilder private func locationRow(_ e: LocationEntry) -> some View {
        let name = e.place?.name ?? "Network"
        let on: Bool = {
            if let p = e.place {
                return app.active.tagFilter == nil && !app.active.showsNetwork
                    && app.active.currentURL.standardizedFileURL.path == p.url.standardizedFileURL.path
            }
            return app.active.showsNetwork
        }()
        HStack(spacing: 8 * s) {
            Image(systemName: e.place?.icon ?? "globe")
                .font(.system(size: 12.5 * s))
                .foregroundStyle(Color.filetor)
                .frame(width: 20 * s)
            Text(name)
                .font(.system(size: 13 * s))
                .foregroundStyle(Color.primary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if e.ejectable, let p = e.place {
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
        .onTapGesture {
            if let p = e.place { app.active.navigate(to: p.url) } else { app.active.showsNetwork = true }
        }
        .onDrag {
            draggingLocation = e.id
            watchDragEnd()
            return NSItemProvider(object: e.id as NSString)
        } preview: {
            dragCard(name)
        }
        .onDrop(of: [.text], delegate: LocationRowDropDelegate(
            id: e.id,
            dragging: $draggingLocation,
            move: { from, to in withAnimation(.easeInOut(duration: 0.22)) { moveLocation(from, onto: to) } },
            draggingSection: draggingSection,
            moveSection: { from in withAnimation(.easeInOut(duration: 0.22)) { moveSection(from, onto: "Locations") } }))
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
        return CloudLocation.all().map { Place(name: $0.name, icon: $0.icon, url: $0.url) }
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
        .contextMenu { sectionsMenu }
        .background(Color.primary.opacity(0.04))
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in tick += 1 }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in tick += 1 }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 11.5 * s, weight: .semibold))
            Image(systemName: isCollapsed(title) ? "chevron.right" : "chevron.down")
                .font(.system(size: 8 * s, weight: .bold))
            Spacer(minLength: 0)
            if hoveredHeader == title && title != "Locations" {
                Text("Hide")
                    .font(.system(size: 11.5 * s))
                    .onTapGesture { setHidden(title, true) }
                    .help("Hide \(title) from the sidebar. Show it again with a right-click in the sidebar.")
            }
        }
        .foregroundStyle(Color.primary.opacity(0.4))
        .padding(.horizontal, 8)
        .padding(.bottom, 2 * s)
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeInOut(duration: 0.15)) { toggleCollapsed(title) } }
        .onHover { hoveredHeader = $0 ? title : (hoveredHeader == title ? nil : hoveredHeader) }
        .onDrag {
            draggingSection = title
            watchDragEnd()
            return NSItemProvider(object: title as NSString)
        } preview: {
            dragCard(title)
        }
    }

    private func section(_ title: String, _ places: [Place], ejectURLs: Set<URL> = [], isFavorites: Bool = false, trailing: AnyView? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2 * s) {
            sectionHeader(title)
            ForEach(isCollapsed(title) ? [] : places) { p in
                let pane = app.active
                let on = pane.tagFilter == nil
                    && pane.currentURL.standardizedFileURL.path == p.url.standardizedFileURL.path
                HStack(spacing: 8 * s) {
                    if isFavorites, themedFolders, ["folder", "menubar.dock.rectangle", "doc", "arrow.down.circle", "house", "square.grid.2x2"].contains(p.icon) {
                        Image(nsImage: ThemedFolderIcon.image(FolderTheme(folderName: p.name) ?? .plain, side: 22 * s, glyph: false))
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 20 * s, height: 20 * s)
                            .id(folderColor)
                    } else {
                        Image(systemName: p.icon)
                            .font(.system(size: 12.5 * s))
                            .foregroundStyle(Color.filetor)
                            .frame(width: 20 * s)
                    }
                    Text(p.name)
                        .font(.system(size: 13 * s))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if ejectURLs.contains(p.url) {
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
                .onTapGesture {
                    app.active.navigate(to: p.url)
                }
                .modifier(FavoriteRowModifier(enabled: isFavorites, url: p.url, app: app, dragging: $draggingFavorite,
                                              card: dragCard(p.name), onDragStart: watchDragEnd))
            }
            if !isCollapsed(title), let trailing { trailing }
        }
    }

    private func tagCircle(_ color: NSColor?) -> some View {
        Group {
            if let color {
                Circle().fill(Color(nsColor: color))
            } else {
                Circle().strokeBorder(Color.primary.opacity(0.45), lineWidth: 1.4)
            }
        }
        .frame(width: 10.5 * s, height: 10.5 * s)
    }

    private var searchesSection: some View {
        let store = SavedSearchStore.shared
        return VStack(alignment: .leading, spacing: 2 * s) {
            sectionHeader("Searches")
            if !isCollapsed("Searches") {
                HStack(spacing: 8 * s) {
                    Image(systemName: "plus")
                        .font(.system(size: 12.5 * s))
                        .foregroundStyle(Color.filetor)
                        .frame(width: 20 * s)
                    Text("New Saved Search…").font(.system(size: 13 * s))
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5 * s)
                .contentShape(Rectangle())
                .onTapGesture { app.savedSearchDialog = SavedSearch(folder: app.active.currentURL.path) }
                ForEach(store.items) { search in
                    let on = app.active.savedSearchID == search.id
                    HStack(spacing: 8 * s) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 12.5 * s))
                            .foregroundStyle(Color.filetor)
                            .frame(width: 20 * s)
                        Text(search.name)
                            .font(.system(size: 13 * s))
                            .foregroundStyle(Color.primary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5 * s)
                    .background(RoundedRectangle(cornerRadius: 7).fill(on ? Color.primary.opacity(0.09) : Color.clear))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if on {
                            app.active.clearTag()
                            app.active.load()
                        } else {
                            app.active.showSaved(search)
                        }
                    }
                    .contextMenu {
                        Button("Edit…") { app.savedSearchDialog = search }
                        Button("Remove from Sidebar") {
                            if on { app.active.clearTag(); app.active.load() }
                            store.remove(search.id)
                        }
                    }
                }
            }
        }
    }

    private var tagsSection: some View {
        let store = TagStore.shared
        return VStack(alignment: .leading, spacing: 2 * s) {
            sectionHeader("Tags")
            if !isCollapsed("Tags") {
                ForEach(store.all) { tag in
                    let on = app.active.tagFilter == tag.name && app.active.savedSearchID == nil
                    HStack(spacing: 8 * s) {
                        tagCircle(tag.color)
                            .frame(width: 20 * s)
                        Text(tag.name)
                            .font(.system(size: 13 * s))
                            .foregroundStyle(Color.primary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5 * s)
                    .background(RoundedRectangle(cornerRadius: 7).fill(on ? Color.primary.opacity(0.09) : Color.clear))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if on {
                            // Second click on the selected tag leaves the tag view.
                            app.active.clearTag()
                            app.active.load()
                        } else {
                            app.active.showTag(tag.name)
                        }
                    }
                    .contextMenu {
                        if tag.color == nil {
                            Button("Remove from Sidebar") { store.remove(tag.name) }
                        }
                    }
                }
            }
        }
    }

    @State private var dropTargeted = false

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
func addDroppedURLs(_ info: DropInfo, to store: FavoritesStore, before: URL?) {
    for provider in info.itemProviders(for: [.fileURL]) {
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            Task { @MainActor in store.insert([url], before: before) }
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
        addDroppedURLs(info, to: app.favorites, before: url)
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
    let favorites: FavoritesStore

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
        addDroppedURLs(info, to: favorites, before: nil)
        return true
    }
}

/// Dropping on a Locations row: a row being moved slides into place; a dragged section is handed to the section order.
struct LocationRowDropDelegate: DropDelegate {
    let id: String
    @Binding var dragging: String?
    let move: (String, String) -> Void
    let draggingSection: String?
    let moveSection: (String) -> Void

    func validateDrop(info: DropInfo) -> Bool { dragging != nil || draggingSection != nil }

    func dropEntered(info: DropInfo) {
        if let d = dragging { if d != id { move(d, id) } }
        else if let s = draggingSection, s != "Locations" { moveSection(s) }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}
