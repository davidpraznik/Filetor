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
            BreadcrumbBar(pane: pane, app: app, onNewTab: onNewTab)
            Divider()
            if app.showFilterBar && pane === app.active && !app.searchFieldVisible {
                FilterBar(pane: pane, app: app, scale: scale)
                Divider()
            }
            table
            if statusBar || pane.searchActive {
                Divider()
                HStack(spacing: 10) {
                    if pane.searching { ProgressView().controlSize(.small) }
                    Text(statusText)
                    if pane.searching {
                        Button("Stop") { pane.stopSearch() }.controlSize(.small)
                    }
                }
                .font(.system(size: 13 * scale))
                .foregroundStyle(Color.primary.opacity(0.55))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7 * scale)
                .background(isActive ? Color.filetor.opacity(0.16) : Color.primary.opacity(0.025))
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
            compact: compactRows,
            showFolder: pane.searchActive
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
        if pane.searchActive {
            let n = pane.searchResults.count
            let results = n == 1 ? "1 result" : "\(n) results"
            let folders = pane.foldersScanned.formatted()
            return pane.searching ? "\(results), searching (\(folders) folders)" : "\(results) in \(folders) folders"
        }
        let total = pane.sortedItems.count
        let selected = pane.selection.count
        let items = total == 1 ? "1 item" : "\(total) items"
        var text = selected > 0 ? "\(selected) of \(items) selected" : items
        let free = freeSpace
        if !free.isEmpty { text += ", " + free }
        return text
    }
}

// MARK: - Filter bar (fallback when the toolbar has no Search field)

struct FilterBar: View {
    @Bindable var pane: PaneModel
    let app: AppModel
    let scale: CGFloat
    @FocusState private var focused: Bool

    private func close() {
        pane.filter = ""
        app.showFilterBar = false
    }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Filter selected pane", text: $pane.filter)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onKeyPress(.escape) { close(); return .handled }
                if !pane.filter.isEmpty {
                    Button { pane.filter = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 12.5 * scale))
            .padding(.horizontal, 8)
            .padding(.vertical, 4 * scale)
            .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
            Picker("", selection: $pane.searchSubfolders) {
                Text("This folder").tag(false)
                Text("Subfolders").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Button("Done") { close() }
                .buttonStyle(.plain)
                .foregroundStyle(Color.filetor)
                .font(.system(size: 12.5 * scale))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .onAppear { focused = true }
        .onChange(of: app.filterBarFocus) { _, _ in focused = true }
    }
}
