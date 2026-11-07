import SwiftUI

struct ContentView: View {
    @State private var model = PaneModel()

    var body: some View {
        @Bindable var pane = model

        NavigationSplitView {
            SidebarView(pane: pane)
                .navigationSplitViewColumnWidth(min: 160, ideal: 200, max: 320)
        } detail: {
            FileListView(pane: pane)
        }
        .navigationTitle(pane.currentURL.lastPathComponent.isEmpty ? "/" : pane.currentURL.lastPathComponent)
        .searchable(text: $pane.filter, prompt: "Filter")
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { pane.goBack() } label: { Image(systemName: "chevron.left") }
                    .disabled(!pane.canGoBack)
                    .keyboardShortcut("[", modifiers: .command)
                    .help("Back")
                Button { pane.goForward() } label: { Image(systemName: "chevron.right") }
                    .disabled(!pane.canGoForward)
                    .keyboardShortcut("]", modifiers: .command)
                    .help("Forward")
                Button { pane.goUp() } label: { Image(systemName: "arrow.up") }
                    .disabled(!pane.canGoUp)
                    .keyboardShortcut(.upArrow, modifiers: .command)
                    .help("Enclosing Folder")
            }
            ToolbarItem {
                Button { pane.toggleHidden() } label: {
                    Image(systemName: pane.showHidden ? "eye" : "eye.slash")
                }
                .keyboardShortcut(".", modifiers: [.command, .shift])
                .help("Show or Hide Hidden Files")
            }
        }
    }
}
