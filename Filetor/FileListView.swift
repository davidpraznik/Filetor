import SwiftUI

struct FileListView: View {
    @Bindable var pane: PaneModel
    let app: AppModel

    @AppStorage("textSize") private var textSize = 1
    @AppStorage("compactRows") private var compactRows = false
    @AppStorage("striped") private var striped = true
    @AppStorage("statusBar") private var statusBar = true
    var isActive = false
    var onNewTab: () -> Void = {}

    private var scale: CGFloat { UIScale.value(textSize) }

    var body: some View {
        VStack(spacing: 0) {
            BreadcrumbBar(pane: pane, onNewTab: onNewTab)
            Divider()
            table
            if statusBar {
                Divider()
                Text(statusText)
                    .font(.system(size: 13 * scale))
                    .foregroundStyle(Color.primary.opacity(0.55))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7 * scale)
                    .background(isActive ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.025))
            }
        }
    }

    @ViewBuilder
    private var table: some View {
        if pane.viewMode == 1 {
            IconGridView(pane: pane, scale: scale)
        } else if pane.viewMode == 2 {
            ColumnsView(pane: pane, scale: scale)
        } else {
            listTable
        }
    }

    private var listTable: some View {
        FileTableView(
            pane: pane, app: app,
            items: pane.sortedItems,
            selection: pane.selection,
            sortOrder: pane.sortOrder,
            scale: scale,
            striped: striped,
            compact: compactRows
        )
        .overlay {
            if let msg = pane.errorMessage {
                ContentUnavailableView("Cannot open folder", systemImage: "lock", description: Text(msg))
            }
        }
    }

    private var freeSpace: String {
        let v = try? pane.currentURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let b = v?.volumeAvailableCapacityForImportantUsage else { return "" }
        return ByteCountFormatter.string(fromByteCount: b, countStyle: .file) + " available"
    }

    private var statusText: String {
        let total = pane.sortedItems.count
        let selected = pane.selection.count
        let items = total == 1 ? "1 item" : "\(total) items"
        var text = selected > 0 ? "\(selected) of \(items) selected" : items
        let free = freeSpace
        if !free.isEmpty { text += ", " + free }
        return text
    }
}
