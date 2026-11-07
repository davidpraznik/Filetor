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

    private var favorites: [Place] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            Place(name: "Home", icon: "house", url: home),
            Place(name: "Desktop", icon: "menubar.dock.rectangle", url: home.appending(path: "Desktop")),
            Place(name: "Documents", icon: "doc", url: home.appending(path: "Documents")),
            Place(name: "Downloads", icon: "arrow.down.circle", url: home.appending(path: "Downloads")),
            Place(name: "Applications", icon: "square.grid.2x2", url: URL(filePath: "/Applications")),
        ]
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
                section("Favorites", favorites)
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

    private func section(_ title: String, _ places: [Place], ejectable: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2 * s) {
            Text(title)
                .font(.system(size: 11.5 * s, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.4))
                .padding(.horizontal, 8)
                .padding(.bottom, 2 * s)
            ForEach(places) { p in
                let on = selection == p.url
                HStack(spacing: 8 * s) {
                    Image(systemName: p.icon)
                        .font(.system(size: 12.5 * s))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 20 * s)
                    Text(p.name)
                        .font(.system(size: 13 * s))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if ejectable && p.url.path != "/" {
                        Button { try? NSWorkspace.shared.unmountAndEjectDevice(at: p.url) } label: {
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
            }
        }
    }

    @State private var dropTargeted = false

    private var shared: some View {
        VStack(alignment: .leading, spacing: 2 * s) {
            Text("Shared")
                .font(.system(size: 11.5 * s, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.4))
                .padding(.horizontal, 8)
                .padding(.bottom, 2 * s)
            HStack(spacing: 8 * s) {
                Image(systemName: "plus")
                    .font(.system(size: 12.5 * s))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 20 * s)
                Text("Connect to Server…").font(.system(size: 13 * s))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5 * s)
            .contentShape(Rectangle())
            .onTapGesture { app.showConnect = true }
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
                    ForEach(app.dropStack, id: \.self) { url in
                        HStack(spacing: 6 * s) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                .resizable().frame(width: 16 * s, height: 16 * s)
                            Text(url.lastPathComponent).font(.system(size: 13 * s)).lineLimit(1)
                            Spacer(minLength: 0)
                            Button { app.dropStack.removeAll { $0 == url } } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 9 * s, weight: .semibold))
                                    .foregroundStyle(Color.primary.opacity(0.45))
                            }
                            .buttonStyle(.plain)
                            .help("Remove from Drop Stack")
                        }
                        .padding(.horizontal, 8)
                        .frame(height: 24 * s)
                        .draggable(url)
                    }
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
                .foregroundStyle(dropTargeted ? Color.accentColor : Color.primary.opacity(0.3))
                .padding(.top, 20 * s)
        )
        .dropDestination(for: URL.self) { urls, _ in
            for u in urls where !app.dropStack.contains(u) { app.dropStack.append(u) }
            return true
        } isTargeted: { dropTargeted = $0 }
    }
}
