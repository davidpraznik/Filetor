import SwiftUI

struct FileListView: View {
    @Bindable var pane: PaneModel
    let app: AppModel

    @AppStorage("textSize") private var textSize = 1
    @AppStorage("foldersFirst") private var foldersFirst = true
    @AppStorage("striped") private var striped = true
    @AppStorage("statusBar") private var statusBar = true
    @AppStorage("listIconSize") private var listIconSize = 17.0
    @AppStorage("showExtensions") private var showExtensions = true
    @AppStorage("iconPreviews") private var iconPreviews = false
    @AppStorage("themedFolders") private var themedFolders = false
    @AppStorage("folderColor") private var folderColor = "multi"
    var isActive = false
    var onNewTab: () -> Void = {}

    /// Icon size in the icon view follows the Row size slider (14...40 maps to 32...128).
    private var gridIconSide: CGFloat { 32 + CGFloat(min(listIconSize, 40) - 14) / 26 * 96 }

    private var scale: CGFloat { UIScale.value(textSize) }

    var body: some View {
        let _ = foldersFirst   // re-sort the lists as soon as the setting changes
        VStack(spacing: 0) {
            BreadcrumbBar(pane: pane, app: app, onNewTab: onNewTab)
            Divider()
            if app.showFilterBar && pane === app.active && !app.searchFieldVisible {
                FilterBar(pane: pane, app: app, scale: scale)
                Divider()
            }
            AIQueryBar(pane: pane, scale: scale)
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

    private var table: some View {
        tableContent.overlay {
            if pane.isOpening {
                VStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Opening folder…")
                        .font(.system(size: 13 * scale))
                        .foregroundStyle(Color.primary.opacity(0.55))
                }
            }
        }
    }

    @ViewBuilder
    private var tableContent: some View {
        if pane.viewMode == 1 {
            IconGridView(pane: pane, scale: scale, foldersFirst: foldersFirst, gridIconSize: gridIconSide, showExtensions: showExtensions, iconPreviews: iconPreviews, themed: themedFolders, tint: FolderTint.index(folderColor))
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
            compact: false,
            iconSize: CGFloat(min(listIconSize, 40)),
            showExtensions: showExtensions,
            previews: iconPreviews,
            themed: themedFolders,
            tint: FolderTint.index(folderColor),
            loading: pane.loading,
            showFolder: pane.searchActive || pane.tagFilter != nil
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
        if let tag = pane.tagFilter {
            let n = pane.sortedItems.count
            let count = n == 1 ? "1 item" : "\(n) items"
            return (pane.tagSearching ? "Searching, " : "") + (pane.savedSearchID != nil ? "\(count) in \(tag)" : "\(count) tagged \(tag)")
        }
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
    @AppStorage("aiProvider") private var aiProvider = 0
    @FocusState private var focused: Bool

    private func close() {
        pane.filter = ""
        app.showFilterBar = false
    }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(aiProvider != 0 ? "Filter or ask AI" : "Filter selected pane", text: $pane.filter)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit { if aiProvider != 0, !pane.filter.isEmpty { pane.askAI(pane.filter) } }
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
            if aiProvider != 0, !pane.filter.isEmpty {
                Button { pane.askAI(pane.filter) } label: { Image(systemName: "sparkles") }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.filetor)
                    .help("Ask AI (↩)")
            }
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

// MARK: - Search described in words

/// Shows what the AI understood from a sentence: the filters as chips, or a short message when it failed.
struct AIQueryBar: View {
    @Bindable var pane: PaneModel
    let scale: CGFloat

    var body: some View {
        if pane.aiAsking || pane.aiQuery != nil || pane.aiMessage != nil {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles").foregroundStyle(Color.filetor)
                    if pane.aiAsking {
                        ProgressView().controlSize(.small)
                        Text("Reading your request…").foregroundStyle(.secondary)
                    } else if let query = pane.aiQuery {
                        ForEach(query.chips, id: \.self) { chip in
                            AIChip(text: chip, scale: scale)
                        }
                        Text("in this folder and its subfolders").foregroundStyle(.secondary).lineLimit(1)
                    } else if let message = pane.aiMessage {
                        Text(message).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if !pane.aiAsking {
                        Button("Clear") { pane.clearAI() }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.filetor)
                    }
                }
                .font(.system(size: 12 * scale))
                .padding(.horizontal, 10)
                .padding(.vertical, 6 * scale)
                Divider()
            }
        }
    }
}
