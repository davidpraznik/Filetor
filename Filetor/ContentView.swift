import SwiftUI

struct ContentView: View {
    let app: AppModel
    @AppStorage("appearance") private var appearance = 0
    @AppStorage("accent") private var accent = 0
    @AppStorage("showSidebar") private var showSidebar = true
    @AppStorage("textSize") private var textSize = 1

    var body: some View {
        @Bindable var model = app
        let pane = app.active

        NavigationSplitView(columnVisibility: $model.sidebarVisibility) {
            SidebarView(app: app)
                .navigationSplitViewColumnWidth(min: 160, ideal: 200 * UIScale.value(textSize), max: 420)
                .safeAreaInset(edge: .top, spacing: 0) { Color.clear.frame(height: 34) }
        } detail: {
            VStack(spacing: 0) {
                CustomToolbar(app: app)
                    .padding(.leading, app.sidebarVisibility == .detailOnly && !app.toolbarModel.contains("sidebar") ? 36 : 0)
                    .padding(.top, app.sidebarVisibility == .detailOnly ? 16 : 0)
                    .overlay(alignment: .leading) {
                        if app.sidebarVisibility == .detailOnly && !app.toolbarModel.contains("sidebar") {
                            Button { app.sidebarVisibility = .all } label: {
                                Image(systemName: "sidebar.left")
                                    .font(.system(size: 16 * UIScale.value(textSize), weight: .light))
                                    .foregroundStyle(Color.primary.opacity(0.6))
                                    .frame(width: 32, height: 32)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("Show Sidebar")
                            .padding(.leading, 10)
                            .padding(.top, 16)
                        }
                    }
                Divider()
                HStack(spacing: 0) {
                    DualPaneView(app: app)
                    if app.showInfo {
                        Divider()
                        InfoPanel(app: app)
                    }
                }
                    .alert("Filetor", isPresented: Binding(
                        get: { app.alert != nil },
                        set: { if !$0 { app.alert = nil } }
                    )) {
                        Button("OK") {}
                    } message: {
                        Text(app.alert ?? "")
                    }
            }
            .ignoresSafeArea(.container, edges: .top)
        }
        .overlay(alignment: .bottom) {
            if app.showShortcuts {
                ShortcutsPanel(app: app).transition(.move(edge: .bottom))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: app.showShortcuts)
        .overlay(alignment: .bottom) {
            ActionsHint(app: app).padding(.bottom, 52)
        }
        .overlay {
            if app.showPalette { CommandPalette(app: app) }
        }
        .preferredColorScheme(appearance == 0 ? .light : (appearance == 1 ? .dark : nil))
        .tint(SettingsSheet.accents[min(max(accent, 0), SettingsSheet.accents.count - 1)])
        .navigationTitle(CloudLocation.title(for: pane.currentURL))
        .toolbar(removing: .sidebarToggle)
        .background(NativeToolbarRemover(trigger: "\(app.sidebarVisibility)"))
        .background {
            // Keyboard shortcuts (the toolbar buttons are drawn by CustomToolbar).
            Group {
                Button("Back") { app.active.goBack() }.keyboardShortcut(.leftArrow, modifiers: .command)
                Button("Forward") { app.active.goForward() }.keyboardShortcut(.rightArrow, modifiers: .command)
                Button("Back ") { app.active.goBack() }.keyboardShortcut("[", modifiers: .command)
                Button("Forward ") { app.active.goForward() }.keyboardShortcut("]", modifiers: .command)
                Button("Enclosing") { app.active.goUp() }.keyboardShortcut(.upArrow, modifiers: .command)
                Button("Hidden") { app.active.toggleHidden() }.keyboardShortcut(".", modifiers: [.command, .shift])
                Button("Reload") { app.active.load() }.keyboardShortcut("r", modifiers: [.command, .option])
                if app.showPalette {
                    Button("Close Palette") { app.showPalette = false }.keyboardShortcut(.escape, modifiers: [])
                } else if app.showShortcuts {
                    Button("Close Shortcuts") { app.showShortcuts = false }.keyboardShortcut(.escape, modifiers: [])
                }
            }
            .opacity(0)
            .allowsHitTesting(false)
        }
        .sheet(item: Binding(
            get: { app.transfers.pending },
            set: { _ in }
        )) { request in
            ConflictSheet(request: request, manager: app.transfers)
        }
        .task {
            app.network.onError = { app.alert = $0 }
            app.network.onMounted = { app.active.navigate(to: $0) }
            app.network.start()
        }
        .task {
            if UserDefaults.standard.object(forKey: "autoUpdate") as? Bool ?? true {
                await app.updater.check()
                if case .available(let v, _) = app.updater.state {
                    app.alert = "Filetor \(v) is available. Open Settings to download it."
                }
            }
        }
        .floatingPanel(isPresented: Binding(get: { model.batchRename != nil }, set: { if !$0 { model.batchRename = nil } })) {
            if let urls = model.batchRename { BatchRenameSheet(app: app, urls: urls) }
        }
        .floatingPanel(isPresented: $model.showConnect) {
            ConnectSheet(app: app)
        }
        .floatingPanel(isPresented: $model.showSettings) {
            SettingsSheet(app: app)
        }
        .floatingPanel(isPresented: Binding(get: { model.report != nil }, set: { if !$0 { model.report = nil } })) {
            ReportPanel(app: app)
        }
        .floatingPanel(isPresented: Binding(get: { model.sync != nil }, set: { if !$0 { model.sync = nil } })) {
            SyncPanel(app: app)
        }
        .floatingPanel(isPresented: $model.showCustomize) {
            CustomizeSheet(app: app)
        }
        .onChange(of: showSidebar) { _, v in app.sidebarVisibility = v ? .all : .detailOnly }
        .onChange(of: app.sidebarVisibility) { _, v in showSidebar = (v != .detailOnly) }
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
            if group.tabs.count > 1 { TabStrip(group: group) }
            FileListView(pane: group.current, app: app, isActive: app.dual && app.activeIndex == index, onNewTab: { group.newTab() })
        }
        .frame(minWidth: 280)
        .simultaneousGesture(TapGesture().onEnded { app.activeIndex = index })
    }
}

struct TabStrip: View {
    let group: PaneGroup
    @AppStorage("textSize") private var textSize = 1

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(group.tabs.enumerated()), id: \.element.id) { i, tab in
                let name = CloudLocation.title(for: tab.currentURL)
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
        .font(.system(size: 12 * UIScale.value(textSize)))
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



/// Removes the native NSToolbar (we draw our own), which also kills the automatic sidebar toggle bubble.
struct NativeToolbarRemover: NSViewRepresentable {
    let trigger: String

    /// Removes the window's native toolbar and keeps removing it whenever SwiftUI or AppKit
    /// brings it back (popovers, palette, sheets, focus changes), so the sidebar button never shows.
    final class Watcher: NSView {
        nonisolated(unsafe) private var observer: NSObjectProtocol?
        nonisolated(unsafe) private var toolbarObservation: NSKeyValueObservation?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let o = observer { NotificationCenter.default.removeObserver(o); observer = nil }
            toolbarObservation = nil
            guard let window else { return }
            window.toolbar = nil
            window.tabbingMode = .disallowed
            // Remove a re-created toolbar immediately (same run loop pass), so the layout never shifts.
            toolbarObservation = window.observe(\.toolbar, options: [.new]) { w, _ in
                MainActor.assumeIsolated {
                    if w.toolbar != nil { w.toolbar = nil }
                }
            }
            observer = NotificationCenter.default.addObserver(forName: NSWindow.didUpdateNotification, object: window, queue: .main) { [weak window] _ in
                MainActor.assumeIsolated {
                    if window?.toolbar != nil { window?.toolbar = nil }
                }
            }
        }

        deinit {
            if let o = observer { NotificationCenter.default.removeObserver(o) }
        }
    }

    func makeNSView(context: Context) -> NSView { Watcher() }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            view.window?.toolbar = nil
        }
    }
}
