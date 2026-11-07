import SwiftUI

struct ContentView: View {
    let app: AppModel
    @State private var showTransfers = false

    var body: some View {
        @Bindable var pane = app.active
        @Bindable var model = app

        NavigationSplitView {
            SidebarView(app: app)
                .navigationSplitViewColumnWidth(min: 160, ideal: 200, max: 320)
        } detail: {
            DualPaneView(app: app)
                .alert("Filetor", isPresented: Binding(
                    get: { app.alert != nil },
                    set: { if !$0 { app.alert = nil } }
                )) {
                    Button("OK") {}
                } message: {
                    Text(app.alert ?? "")
                }
        }
        .navigationTitle(pane.currentURL.lastPathComponent.isEmpty ? "/" : pane.currentURL.lastPathComponent)
        .modifier(HideNativeTitle())
        .toolbar(id: "filetor.main") {
            // Navigation
            ToolbarItem(id: "backForward", placement: .navigation) {
                ControlGroup {
                    Button { app.active.goBack() } label: { Image(systemName: "chevron.left") }
                        .disabled(!pane.canGoBack)
                        .keyboardShortcut("[", modifiers: .command)
                        .help("Back")
                    Button { app.active.goForward() } label: { Image(systemName: "chevron.right") }
                        .disabled(!pane.canGoForward)
                        .keyboardShortcut("]", modifiers: .command)
                        .help("Forward")
                } label: {
                    Label("Back/Forward", systemImage: "chevron.left.chevron.right")
                }
            }
            ToolbarItem(id: "enclosing", placement: .navigation) {
                Button { app.active.goUp() } label: { Label("Enclosing Folder", systemImage: "arrow.up") }
                    .disabled(!pane.canGoUp)
                    .keyboardShortcut(.upArrow, modifiers: .command)
                    .help("Enclosing Folder")
            }
            .defaultCustomization(.hidden)
            ToolbarItem(id: "title", placement: .navigation) {
                // On macOS 14 the native window title stays and this item is empty.
                if #available(macOS 15, *) {
                    Text(pane.currentURL.lastPathComponent.isEmpty ? "/" : pane.currentURL.lastPathComponent)
                        .font(.headline)
                        .lineLimit(1)
                }
            }

            // Selection actions (hidden by default, available in Customize Toolbar)
            ToolbarItem(id: "quickLook", placement: .primaryAction) {
                Button { app.quickLook(pane.selection) } label: { Label("Quick Look", systemImage: "eye") }
                    .disabled(pane.selection.isEmpty)
                    .help("Quick Look")
            }
            .defaultCustomization(.hidden)
            ToolbarItem(id: "hiddenFiles", placement: .primaryAction) {
                Button { app.active.toggleHidden() } label: {
                    Label("Hidden Files", systemImage: pane.showHidden ? "eye" : "eye.slash")
                }
                .keyboardShortcut(".", modifiers: [.command, .shift])
                .help("Show or Hide Hidden Files")
            }
            .defaultCustomization(.hidden)
            ToolbarItem(id: "newFile", placement: .primaryAction) {
                Button { app.newFile() } label: { Label("New File", systemImage: "doc.badge.plus") }
                    .help("New File")
            }
            .defaultCustomization(.hidden)
            ToolbarItem(id: "newTab", placement: .primaryAction) {
                Button { app.newTab() } label: { Label("New Tab", systemImage: "plus") }
                    .help("New Tab")
            }
            .defaultCustomization(.hidden)
            ToolbarItem(id: "open", placement: .primaryAction) {
                Button { app.openSelection() } label: { Label("Open", systemImage: "folder") }
                    .disabled(pane.selection.isEmpty)
                    .help("Open")
            }
            .defaultCustomization(.hidden)
            ToolbarItem(id: "rename", placement: .primaryAction) {
                Button { app.beginRename(pane.selection) } label: { Label("Rename", systemImage: "pencil") }
                    .disabled(pane.selection.isEmpty)
                    .help("Rename")
            }
            .defaultCustomization(.hidden)
            ToolbarItem(id: "duplicate", placement: .primaryAction) {
                Button { app.duplicate(pane.selection) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                    .disabled(pane.selection.isEmpty)
                    .help("Duplicate")
            }
            .defaultCustomization(.hidden)
            ToolbarItem(id: "copy", placement: .primaryAction) {
                Button { app.transfer(pane.selection, move: false) } label: { Label("Copy", systemImage: "doc.on.doc") }
                    .disabled(pane.selection.isEmpty || !app.dual)
                    .help("Copy to Other Pane")
            }
            .defaultCustomization(.hidden)
            ToolbarItem(id: "move", placement: .primaryAction) {
                Button { app.transfer(pane.selection, move: true) } label: { Label("Move", systemImage: "arrow.right.doc.on.clipboard") }
                    .disabled(pane.selection.isEmpty || !app.dual)
                    .help("Move to Other Pane")
            }
            .defaultCustomization(.hidden)
            ToolbarItem(id: "trash", placement: .primaryAction) {
                Button { app.trash(pane.selection) } label: { Label("Move to Trash", systemImage: "trash") }
                    .disabled(pane.selection.isEmpty)
                    .help("Move to Trash")
            }
            .defaultCustomization(.hidden)
            ToolbarItem(id: "compress", placement: .primaryAction) {
                Button { app.compress(pane.selection) } label: { Label("Compress", systemImage: "arrow.down.right.and.arrow.up.left") }
                    .disabled(pane.selection.isEmpty)
                    .help("Compress")
            }
            .defaultCustomization(.hidden)
            ToolbarItem(id: "decompress", placement: .primaryAction) {
                Button { app.decompress(pane.selection) } label: { Label("Decompress", systemImage: "arrow.up.left.and.arrow.down.right") }
                    .disabled(pane.selection.isEmpty)
                    .help("Decompress")
            }
            .defaultCustomization(.hidden)
            ToolbarItem(id: "folderSize", placement: .primaryAction) {
                Button { app.folderSize(pane.selection) } label: { Label("Folder Size", systemImage: "chart.bar") }
                    .disabled(pane.selection.isEmpty)
                    .help("Folder Size")
            }
            .defaultCustomization(.hidden)

            // Default set
            ToolbarItem(id: "airDrop", placement: .primaryAction) {
                Button { app.airDrop(pane.selection) } label: { Label("AirDrop", systemImage: "airplayaudio") }
                    .disabled(pane.selection.isEmpty)
                    .help("AirDrop")
            }
            ToolbarItem(id: "terminal", placement: .primaryAction) {
                Button { app.openTerminal() } label: { Label("Terminal", systemImage: "apple.terminal") }
                    .help("Open Terminal Here")
            }
            ToolbarItem(id: "touch", placement: .primaryAction) {
                Button { app.touch(pane.selection) } label: { Label("Touch", systemImage: "clock") }
                    .disabled(pane.selection.isEmpty)
                    .help("Set Modification Date to Now")
            }
            ToolbarItem(id: "customize", placement: .primaryAction) {
                Button {
                    NSApp.sendAction(#selector(NSWindow.runToolbarCustomizationPalette(_:)), to: nil, from: nil)
                } label: { Label("Customize", systemImage: "gearshape") }
                    .help("Customize Toolbar")
            }
            ToolbarItem(id: "reload", placement: .primaryAction) {
                Button { app.active.load() } label: { Label("Reload", systemImage: "arrow.clockwise") }
                    .keyboardShortcut("r", modifiers: [.command, .option])
                    .help("Reload")
            }
            ToolbarItem(id: "newFolder", placement: .primaryAction) {
                Button { app.newFolder() } label: { Label("New Folder", systemImage: "folder.badge.plus") }
                    .help("New Folder")
            }
            ToolbarItem(id: "copyPath", placement: .primaryAction) {
                Button { app.copyPath() } label: { Label("Copy Path", systemImage: "link") }
                    .help("Copy Path")
            }
            ToolbarItem(id: "swapPanes", placement: .primaryAction) {
                Button { app.swapPanes() } label: { Label("Swap Panes", systemImage: "arrow.left.arrow.right") }
                    .disabled(!app.dual)
                    .help("Swap Panes")
            }
            ToolbarItem(id: "dual", placement: .primaryAction) {
                Button { app.dual.toggle() } label: {
                    Label("Dual Browser", systemImage: "rectangle.split.2x1")
                }
                .help("Dual Pane")
            }
            ToolbarItem(id: "filter", placement: .primaryAction) {
                FilterField(text: $pane.filter)
            }
            // Transfer indicator: last item, far right, never moved into the overflow menu.
            ToolbarItem(id: "transfers", placement: .primaryAction) {
                if app.transfers.hasActive {
                    Button { showTransfers.toggle() } label: {
                        Label("\(Int(app.transfers.overall * 100))%", systemImage: "arrow.left.arrow.right.circle")
                    }
                    .help("Transfers")
                    .popover(isPresented: $showTransfers) {
                        TransferList(manager: app.transfers)
                    }
                }
            }
            .customizationBehavior(.disabled)
        }
        .background {
            // Extra shortcuts that work on every keyboard layout.
            Group {
                Button("Back") { app.active.goBack() }
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                Button("Forward") { app.active.goForward() }
                    .keyboardShortcut(.rightArrow, modifiers: .command)
            }
            .opacity(0)
            .allowsHitTesting(false)
        }
        .alert("Rename", isPresented: Binding(
            get: { app.renameTarget != nil },
            set: { if !$0 { app.renameTarget = nil } }
        )) {
            TextField("Name", text: $model.renameText)
            Button("Rename") { app.commitRename() }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: Binding(
            get: { app.transfers.pending },
            set: { _ in }
        )) { request in
            ConflictSheet(request: request, manager: app.transfers)
        }
        .onChange(of: app.dual) { _, dual in
            if !dual { app.activeIndex = 0 }
        }
    }
}

struct PaneContainer: View {
    let app: AppModel
    let index: Int

    var body: some View {
        let group = app.groups[index]
        VStack(spacing: 0) {
            TabStrip(group: group)
            FileListView(pane: group.current, app: app)
        }
        .frame(minWidth: 280)
        .overlay {
            if app.dual && app.activeIndex == index {
                Rectangle()
                    .strokeBorder(Color.accentColor.opacity(0.7), lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
        .simultaneousGesture(TapGesture().onEnded { app.activeIndex = index })
    }
}

struct TabStrip: View {
    let group: PaneGroup

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(group.tabs.enumerated()), id: \.element.id) { i, tab in
                let name = tab.currentURL.lastPathComponent.isEmpty ? "/" : tab.currentURL.lastPathComponent
                HStack(spacing: 6) {
                    Text(name).lineLimit(1)
                    if group.tabs.count > 1 {
                        Button { group.close(at: i) } label: {
                            Image(systemName: "xmark").font(.caption2)
                        }
                        .buttonStyle(.plain)
                        .help("Close Tab")
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .frame(maxWidth: 170)
                .background(i == group.selected ? Color.primary.opacity(0.12) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
                .onTapGesture { group.selected = i }
            }
            Button { group.newTab() } label: { Image(systemName: "plus") }
                .buttonStyle(.plain)
                .padding(.horizontal, 6)
                .help("New Tab")
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.bar)
    }
}

struct DualPaneView: View {
    let app: AppModel
    @State private var ratio: Double = 0.5

    private let handle: CGFloat = 7
    private let minPane: CGFloat = 280

    var body: some View {
        GeometryReader { geo in
            let usable = max(geo.size.width - handle, 1)
            if app.dual {
                let lo = min(minPane / usable, 0.5)
                let r = min(max(ratio, lo), 1 - lo)
                HStack(spacing: 0) {
                    PaneContainer(app: app, index: 0)
                        .frame(width: usable * r)
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: handle)
                        .overlay { Divider() }
                        .contentShape(Rectangle())
                        .onHover { inside in
                            if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                        }
                        .gesture(
                            DragGesture(minimumDistance: 1, coordinateSpace: .named("dualSplit"))
                                .onChanged { v in
                                    ratio = min(max((v.location.x - handle / 2) / usable, lo), 1 - lo)
                                }
                        )
                        .onTapGesture(count: 2) { ratio = 0.5 }
                    PaneContainer(app: app, index: 1)
                        .frame(width: usable * (1 - r))
                }
                .coordinateSpace(name: "dualSplit")
            } else {
                PaneContainer(app: app, index: 0)
            }
        }
    }
}

struct FilterField: View {
    @Binding var text: String

    private var field: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Filter", text: $text).textFieldStyle(.plain)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 160)
    }

    var body: some View {
        if #available(macOS 26, *) {
            field
        } else {
            field
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        }
    }
}

struct HideNativeTitle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.toolbar(removing: .title)
        } else {
            content
        }
    }
}
