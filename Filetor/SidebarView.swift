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

    private var devices: [Place] {
        [Place(name: "Macintosh HD", icon: "internaldrive", url: URL(filePath: "/"))]
    }

    var body: some View {
        List(selection: $selection) {
            Section("Favorites") {
                ForEach(favorites) { p in
                    Label(p.name, systemImage: p.icon).tag(p.url)
                }
            }
            Section("Devices") {
                ForEach(devices) { p in
                    Label(p.name, systemImage: p.icon).tag(p.url)
                }
            }
        }
        .listStyle(.sidebar)
        .font(.system(size: 13 * UIScale.value(textSize)))
        .environment(\.sidebarRowSize, UIScale.value(textSize) >= 1.4 ? .large : .medium)
        .onChange(of: selection) { _, new in
            if let new { app.active.navigate(to: new) }
        }
    }
}
