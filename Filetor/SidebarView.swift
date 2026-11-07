import SwiftUI

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

    private var s: CGFloat { UIScale.value(textSize) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14 * s) {
                dropStack
                section("Devices", devices, ejectable: true)
                shared
                section("Favorites", favorites, isFavorites: true)
                    .dropDestination(for: URL.self) { urls, _ in
                        app.favorites.insert(urls, before: nil)
                        return true
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
                .modifier(FavoriteRowModifier(enabled: isFavorites, url: p.url, app: app))
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

/// Drag to reorder, drop folders to add, right-click to remove (Favorites only).
struct FavoriteRowModifier: ViewModifier {
    let enabled: Bool
    let url: URL
    let app: AppModel

    func body(content: Content) -> some View {
        if enabled {
            content
                .draggable(url)
                .dropDestination(for: URL.self) { urls, _ in
                    app.favorites.insert(urls, before: url)
                    return true
                }
                .contextMenu {
                    Button("Remove from Favorites") { app.favorites.remove(url) }
                }
        } else {
            content
        }
    }
}
