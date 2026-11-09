import SwiftUI

/// One command in the palette.
struct AppCommand: Identifiable {
    let id: String
    let title: String
    var keys = ""
    var isEnabled: @MainActor (AppModel) -> Bool = { _ in true }
    let run: @MainActor (AppModel) -> Void
}

/// Commands offered by the palette (⌘K). Add new commands here.
@MainActor enum CommandCatalog {
    @MainActor private static func hasSelection(_ app: AppModel) -> Bool { !app.active.selection.isEmpty }
    @MainActor private static func hasImage(_ app: AppModel) -> Bool { app.active.selection.contains { FileTools.isImage($0) } }
    @MainActor private static func hasArchive(_ app: AppModel) -> Bool { app.active.selection.contains { FileTools.isArchive($0) } }

    static let all: [AppCommand] = [
        AppCommand(id: "newFolder", title: "New Folder", keys: "⇧ ⌘ N") { $0.newFolder() },
        AppCommand(id: "rename", title: "Rename…", keys: "F2", isEnabled: hasSelection) { $0.beginRename($0.active.selection) },
        AppCommand(id: "duplicate", title: "Duplicate", keys: "⌘ D", isEnabled: hasSelection) { $0.duplicate($0.active.selection) },
        AppCommand(id: "copyTo", title: "Copy to…", isEnabled: hasSelection) { $0.chooseFolderAndTransfer($0.active.selection, move: false) },
        AppCommand(id: "moveTo", title: "Move to…", isEnabled: hasSelection) { $0.chooseFolderAndTransfer($0.active.selection, move: true) },
        AppCommand(id: "trash", title: "Move to Trash", keys: "⌘ ⌫", isEnabled: hasSelection) { $0.trash($0.active.selection) },
        AppCommand(id: "copyOther", title: "Copy to Other Pane", keys: "F5", isEnabled: hasSelection) { $0.transfer($0.active.selection, move: false) },
        AppCommand(id: "moveOther", title: "Move to Other Pane", keys: "F6", isEnabled: hasSelection) { $0.transfer($0.active.selection, move: true) },
        AppCommand(id: "info", title: "Get Info", keys: "⌘ I", isEnabled: hasSelection) { $0.getInfo($0.active.selection) },
        AppCommand(id: "compress", title: "Compress", isEnabled: hasSelection) { $0.compress($0.active.selection) },
        AppCommand(id: "decompress", title: "Decompress", isEnabled: hasArchive) { $0.decompress($0.active.selection) },
        AppCommand(id: "rotL", title: "Rotate Left", isEnabled: hasImage) { $0.rotateImages($0.active.selection, degrees: 270) },
        AppCommand(id: "rotR", title: "Rotate Right", isEnabled: hasImage) { $0.rotateImages($0.active.selection, degrees: 90) },
        AppCommand(id: "toPNG", title: "Convert Image to PNG", isEnabled: hasImage) { $0.convertImages($0.active.selection, format: "png", ext: "png") },
        AppCommand(id: "toJPEG", title: "Convert Image to JPEG", isEnabled: hasImage) { $0.convertImages($0.active.selection, format: "jpeg", ext: "jpg") },
        AppCommand(id: "toHEIC", title: "Convert Image to HEIC", isEnabled: hasImage) { $0.convertImages($0.active.selection, format: "heic", ext: "heic") },
        AppCommand(id: "toTIFF", title: "Convert Image to TIFF", isEnabled: hasImage) { $0.convertImages($0.active.selection, format: "tiff", ext: "tiff") },
        AppCommand(id: "dupes", title: "Find Duplicates…") { $0.findDuplicates() },
        AppCommand(id: "compare", title: "Compare Folders…") { $0.compareFolders() },
        AppCommand(id: "connect", title: "Connect to Server…") { $0.showConnect = true },
        AppCommand(id: "copyPath", title: "Copy Path") { $0.copyPath() },
        AppCommand(id: "swap", title: "Swap Panes") { $0.swapPanes() },
        AppCommand(id: "reload", title: "Reload", keys: "⌥ ⌘ R") { $0.active.load() },
        AppCommand(id: "hidden", title: "Show or Hide Hidden Files", keys: "⇧ ⌘ .") { $0.active.toggleHidden() },
        AppCommand(id: "search", title: "Search", keys: "⌘ F") { $0.activateSearch() },
        AppCommand(id: "newTab", title: "New Tab", keys: "⌘ T") { $0.newTab() },
        AppCommand(id: "closeTab", title: "Close Tab", keys: "⌘ W") { $0.closeTab() },
        AppCommand(id: "infoPanel", title: "Show or Hide Info Panel", keys: "⌥ ⌘ I") { $0.showInfo.toggle() },
        AppCommand(id: "shortcuts", title: "Keyboard Shortcuts", keys: "⌥ ⌘ K") { $0.showShortcuts.toggle() },
        AppCommand(id: "customize", title: "Customize Toolbar…") { $0.showCustomize = true },
        AppCommand(id: "restoreToolbar", title: "Restore Toolbar Defaults") { $0.toolbarModel.restoreDefaults() },
        AppCommand(id: "settings", title: "Settings…", keys: "⌘ ,") { $0.showSettings = true },
    ]
}

/// Popup with a search field listing all commands (⌘K).
struct CommandPalette: View {
    let app: AppModel
    @State private var query = ""
    @State private var index = 0
    @FocusState private var focused: Bool
    @AppStorage("textSize") private var textSize = 1

    private var s: CGFloat { UIScale.value(textSize) }

    private var results: [(cmd: AppCommand, enabled: Bool)] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let matches = CommandCatalog.all.filter { q.isEmpty || $0.title.localizedCaseInsensitiveContains(q) }
        let pairs = matches.map { (cmd: $0, enabled: $0.isEnabled(app)) }
        let prefix = pairs.filter { q.isEmpty || $0.cmd.title.lowercased().hasPrefix(q.lowercased()) }
        let rest = pairs.filter { !(q.isEmpty || $0.cmd.title.lowercased().hasPrefix(q.lowercased())) }
        let ordered = prefix + rest
        return ordered.filter(\.enabled) + ordered.filter { !$0.enabled }
    }

    private func run(_ i: Int) {
        let list = results
        guard list.indices.contains(i), list[i].enabled else { return }
        let cmd = list[i].cmd
        app.showPalette = false
        DispatchQueue.main.async { cmd.run(app) }
    }

    var body: some View {
        let list = results
        ZStack(alignment: .top) {
            Color.black.opacity(0.16)
                .ignoresSafeArea()
                .onTapGesture { app.showPalette = false }
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search actions…", text: $query)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16 * s))
                        .focused($focused)
                        .onSubmit { run(index) }
                        .onKeyPress(.downArrow) { index = min(index + 1, max(list.count - 1, 0)); return .handled }
                        .onKeyPress(.upArrow) { index = max(index - 1, 0); return .handled }
                        .onChange(of: query) { _, _ in index = 0 }
                }
                .padding(.horizontal, 18)
                .frame(height: 54 * s)
                Divider()
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(list.enumerated()), id: \.element.cmd.id) { i, r in
                                row(r.cmd, enabled: r.enabled, selected: i == index)
                                    .id(r.cmd.id)
                                    .onTapGesture { run(i) }
                            }
                            if list.isEmpty {
                                Text("No matching commands")
                                    .font(.system(size: 13.5 * s))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, minHeight: 60 * s)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .frame(maxHeight: 380 * s)
                    .onChange(of: index) { _, new in
                        if list.indices.contains(new) { proxy.scrollTo(list[new].cmd.id) }
                    }
                }
                Divider()
                HStack(spacing: 18) {
                    Text("↑ ↓ to move")
                    Text("Return to run")
                    Text("Esc to close")
                    Spacer(minLength: 0)
                }
                .font(.system(size: 12 * s))
                .foregroundStyle(Color.primary.opacity(0.5))
                .padding(.horizontal, 18)
                .frame(height: 36 * s)
                .background(Color.primary.opacity(0.03))
            }
            .frame(width: 560 * s)
            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.12)))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.3), radius: 24, y: 10)
            .padding(.top, 92)
        }
        .onAppear { focused = true }
    }

    private func row(_ cmd: AppCommand, enabled: Bool, selected: Bool) -> some View {
        HStack(spacing: 0) {
            Text(cmd.title)
                .font(.system(size: 14 * s))
                .foregroundStyle(enabled ? Color.primary : Color.primary.opacity(0.35))
            Spacer(minLength: 12)
            if !cmd.keys.isEmpty {
                HStack(spacing: 4) {
                    ForEach(Array(cmd.keys.split(separator: " ").enumerated()), id: \.offset) { _, k in
                        Text(String(k))
                            .font(.system(size: 12 * s))
                            .foregroundStyle(enabled ? Color.primary : Color.primary.opacity(0.35))
                            .frame(minWidth: 24 * s, minHeight: 22 * s)
                            .padding(.horizontal, 2)
                            .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.06)))
                            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.1)))
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 38 * s)
        .background(RoundedRectangle(cornerRadius: 8).fill(selected && enabled ? Color.filetor.opacity(0.14) : Color.clear))
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
    }
}

/// One-time hint shown after the first launch: "Press ⌘K to browse actions".
struct ActionsHint: View {
    let app: AppModel
    @AppStorage("actionsHintShown") private var shown = false
    @AppStorage("textSize") private var textSize = 1
    @State private var visible = false

    private var s: CGFloat { UIScale.value(textSize) }

    var body: some View {
        ZStack {
            // Keeps the view alive so the .task below runs even while the hint is hidden.
            Color.clear.frame(width: 1, height: 1).allowsHitTesting(false)
            if visible {
                HStack(spacing: 10) {
                    Text("Press")
                    HStack(spacing: 4) {
                        key("⌘")
                        key("K")
                    }
                    Text("to browse actions")
                    Button { withAnimation { visible = false } } label: {
                        Text("✕")
                            .font(.system(size: 11 * s))
                            .frame(width: 24 * s, height: 24 * s)
                            .background(Circle().fill(Color.white.opacity(0.14)))
                    }
                    .buttonStyle(.plain)
                    .padding(.leading, 4)
                }
                .font(.system(size: 14 * s))
                .foregroundStyle(.white)
                .padding(.leading, 18)
                .padding(.trailing, 10)
                .frame(height: 44 * s)
                .background(Capsule().fill(Color(white: 0.11)))
                .shadow(color: .black.opacity(0.28), radius: 15, y: 10)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .task {
            guard !shown else { return }
            try? await Task.sleep(for: .seconds(1))
            shown = true
            withAnimation { visible = true }
            try? await Task.sleep(for: .seconds(12))
            withAnimation { visible = false }
        }
        .onChange(of: app.showPalette) { _, on in
            if on { withAnimation { visible = false } }
        }
    }

    private func key(_ k: String) -> some View {
        Text(k)
            .font(.system(size: 12.5 * s))
            .padding(.horizontal, 6)
            .frame(minWidth: 24 * s, minHeight: 24 * s)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.16)))
    }
}
