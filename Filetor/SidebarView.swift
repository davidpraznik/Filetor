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

    private var s: CGFloat { UIScale.value(textSize) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14 * s) {
                section("Favorites", favorites)
                section("Devices", devices)
            }
            .padding(.horizontal, 10)
            .padding(.top, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .onChange(of: selection) { _, new in
            if let new { app.active.navigate(to: new) }
        }
    }

    private func section(_ title: String, _ places: [Place]) -> some View {
        VStack(alignment: .leading, spacing: 2 * s) {
            Text(title)
                .font(.system(size: 11.5 * s, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.bottom, 2 * s)
            ForEach(places) { p in
                let on = selection == p.url
                HStack(spacing: 8 * s) {
                    Image(systemName: p.icon)
                        .font(.system(size: 14 * s))
                        .foregroundStyle(on ? Color.white : Color.accentColor)
                        .frame(width: 22 * s)
                    Text(p.name)
                        .font(.system(size: 13.5 * s))
                        .foregroundStyle(on ? Color.white : Color.primary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5 * s)
                .background(RoundedRectangle(cornerRadius: 7).fill(on ? Color.accentColor : Color.clear))
                .contentShape(Rectangle())
                .onTapGesture { selection = p.url }
            }
        }
    }
}
