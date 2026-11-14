import SwiftUI

/// One tab of the shortcuts panel.
struct ShortcutGroup: Identifiable {
    let title: String
    let entries: [(name: String, keys: String)]
    var id: String { title }
}

/// All shortcuts shown in the panel. Keep this list in sync when a shortcut is added or changed.
enum Shortcuts {
    static let groups: [ShortcutGroup] = [
        ShortcutGroup(title: "Navigation", entries: [
            ("Back", "⌘ ←"),
            ("Forward", "⌘ →"),
            ("Back (alternative)", "⌘ ["),
            ("Forward (alternative)", "⌘ ]"),
            ("Enclosing Folder", "⌘ ↑"),
            ("Reload", "⌥ ⌘ R"),
            ("Show or Hide Hidden Files", "⇧ ⌘ ."),
            ("Search", "⌘ F"),
        ]),
        ShortcutGroup(title: "Files", entries: [
            ("New Folder", "⇧ ⌘ N"),
            ("Rename", "F2"),
            ("Rename (selected file)", "Return"),
            ("Duplicate", "⌘ D"),
            ("Copy", "⌘ C"),
            ("Paste", "⌘ V"),
            ("Move to Trash", "⌘ ⌫"),
            ("Delete Immediately", "⌥ ⌘ ⌫"),
            ("Undo", "⌘ Z"),
            ("Redo", "⇧ ⌘ Z"),
            ("Quick Look", "Space"),
            ("Copy to Other Pane", "F5"),
            ("Move to Other Pane", "F6"),
        ]),
        ShortcutGroup(title: "Tools", entries: [
            ("Get Info", "⌘ I"),
            ("Share (right-click)", "—"),
            ("Compress", "—"),
            ("Decompress", "—"),
            ("Rotate Left", "—"),
            ("Rotate Right", "—"),
            ("Convert Image", "—"),
            ("Find Duplicates", "—"),
            ("Compare Folders", "—"),
            ("Synchronize", "—"),
        ]),
        ShortcutGroup(title: "View", entries: [
            ("Show or Hide Info Panel", "⌥ ⌘ I"),
            ("Actions", "⌘ K"),
            ("Keyboard Shortcuts", "⌥ ⌘ K"),
            ("Customize Toolbar", "—"),
            ("Restore Toolbar Defaults", "—"),
        ]),
        ShortcutGroup(title: "Window", entries: [
            ("New Tab", "⌘ T"),
            ("Close Tab", "⌘ W"),
            ("New Window", "⌘ N"),
            ("Settings", "⌘ ,"),
        ]),
    ]
}

/// Bottom panel listing the shortcuts in tabs (⌥⌘K).
struct ShortcutsPanel: View {
    let app: AppModel
    @State private var selected = "Navigation"
    @AppStorage("textSize") private var textSize = 1

    private var s: CGFloat { UIScale.value(textSize) }
    private let perColumn = 4

    private var columns: [[(name: String, keys: String)]] {
        let entries = Shortcuts.groups.first { $0.title == selected }?.entries ?? []
        return (0..<3).map { c in
            let start = c * perColumn
            guard start < entries.count else { return [] }
            return Array(entries[start..<min(start + perColumn, entries.count)])
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 6) {
                ForEach(Shortcuts.groups) { g in
                    let on = selected == g.title
                    Text(g.title)
                        .font(.system(size: 13 * s, weight: on ? .semibold : .regular))
                        .foregroundStyle(on ? Color.primary : Color.primary.opacity(0.55))
                        .padding(.horizontal, 12)
                        .padding(.top, 14 * s)
                        .padding(.bottom, 12 * s)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(on ? Color.filetor : Color.clear).frame(height: 2)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { selected = g.title }
                }
                Spacer(minLength: 0)
                Text("⌥ ⌘ K to close")
                    .font(.system(size: 12 * s))
                    .foregroundStyle(Color.primary.opacity(0.5))
                Button { app.showShortcuts = false } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9 * s, weight: .bold))
                        .foregroundStyle(Color.primary.opacity(0.55))
                        .frame(width: 22 * s, height: 22 * s)
                        .background(Circle().fill(Color.primary.opacity(0.07)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 22)
            Divider()
            HStack(alignment: .top, spacing: 40) {
                ForEach(0..<3, id: \.self) { c in
                    VStack(spacing: 0) {
                        ForEach(Array(columns[c].enumerated()), id: \.offset) { _, e in
                            row(e.name, e.keys)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 4)
            Spacer(minLength: 0)
        }
        .frame(height: 232 * s)
        .background(Color(nsColor: .windowBackgroundColor))
        .shadow(color: .black.opacity(0.12), radius: 14, y: -4)
    }

    private func row(_ name: String, _ keys: String) -> some View {
        HStack(spacing: 0) {
            Text(name)
                .font(.system(size: 13.5 * s))
                .lineLimit(1)
                .frame(width: 190 * s, alignment: .leading)
            if keys == "—" {
                Text("—").font(.system(size: 13 * s)).foregroundStyle(Color.primary.opacity(0.35))
            } else {
                HStack(spacing: 4) {
                    ForEach(Array(keys.split(separator: " ").enumerated()), id: \.offset) { _, k in
                        Text(String(k))
                            .font(.system(size: 12.5 * s))
                            .frame(minWidth: 26 * s, minHeight: 24 * s)
                            .padding(.horizontal, 3)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.1)))
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(height: 40 * s)
        .overlay(alignment: .bottom) { Divider().opacity(0.6) }
    }
}
