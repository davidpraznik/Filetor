import SwiftUI

struct ContentView: View {
    @State private var pane = PaneModel()

    var body: some View {
        NavigationSplitView {
            SidebarView(pane: pane)
                .navigationSplitViewColumnWidth(min: 160, ideal: 200, max: 320)
        } detail: {
            FileListView(pane: pane)
        }
        .navigationTitle(pane.currentURL.lastPathComponent.isEmpty ? "/" : pane.currentURL.lastPathComponent)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { pane.goBack() } label: { Image(systemName: "chevron.left") }
                    .disabled(!pane.canGoBack)
                Button { pane.goForward() } label: { Image(systemName: "chevron.right") }
                    .disabled(!pane.canGoForward)
                Button { pane.goUp() } label: { Image(systemName: "arrow.up") }
                    .disabled(!pane.canGoUp)
            }
        }
    }
}
