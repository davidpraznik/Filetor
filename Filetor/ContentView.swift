import SwiftUI

struct ContentView: View {
    @State private var app = AppModel()

    var body: some View {
        @Bindable var pane = app.active

        NavigationSplitView {
            SidebarView(app: app)
                .navigationSplitViewColumnWidth(min: 160, ideal: 200, max: 320)
        } detail: {
            DualPaneView(app: app)
        }
        .navigationTitle(pane.currentURL.lastPathComponent.isEmpty ? "/" : pane.currentURL.lastPathComponent)
        .searchable(text: $pane.filter, prompt: "Filter")
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { app.active.goBack() } label: { Image(systemName: "chevron.left") }
                    .disabled(!pane.canGoBack)
                    .keyboardShortcut("[", modifiers: .command)
                    .help("Back")
                Button { app.active.goForward() } label: { Image(systemName: "chevron.right") }
                    .disabled(!pane.canGoForward)
                    .keyboardShortcut("]", modifiers: .command)
                    .help("Forward")
                Button { app.active.goUp() } label: { Image(systemName: "arrow.up") }
                    .disabled(!pane.canGoUp)
                    .keyboardShortcut(.upArrow, modifiers: .command)
                    .help("Enclosing Folder")
            }
            ToolbarItemGroup {
                Button { app.dual.toggle() } label: {
                    Image(systemName: "rectangle.split.2x1")
                }
                .help("Dual Pane")
                Button { app.active.toggleHidden() } label: {
                    Image(systemName: pane.showHidden ? "eye" : "eye.slash")
                }
                .keyboardShortcut(".", modifiers: [.command, .shift])
                .help("Show or Hide Hidden Files")
            }
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
        .onChange(of: app.dual) { _, dual in
            if !dual { app.activeIndex = 0 }
        }
    }
}

struct PaneContainer: View {
    let app: AppModel
    let index: Int

    var body: some View {
        FileListView(pane: app.panes[index])
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
