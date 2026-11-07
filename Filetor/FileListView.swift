import SwiftUI

struct FileListView: View {
    @Bindable var pane: PaneModel
    let app: AppModel

    @AppStorage("textSize") private var textSize = 1
    @AppStorage("compactRows") private var compactRows = false
    @AppStorage("striped") private var striped = true
    @AppStorage("statusBar") private var statusBar = true

    private var scale: CGFloat { UIScale.value(textSize) }

    var body: some View {
        Table(pane.sortedItems, selection: $pane.selection, sortOrder: $pane.sortOrder) {
            TableColumn("Name", value: \.name) { item in
                HStack(spacing: 6) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                        .resizable()
                        .frame(width: 16 * scale, height: 16 * scale)
                    Text(item.name).lineLimit(1)
                }
                .padding(.vertical, compactRows ? 0 : 2)
            }
            TableColumn("Date Modified", value: \.modified) { item in
                Text(item.modified.formatted(date: .abbreviated, time: .shortened))
                    .foregroundStyle(.secondary)
            }
            .width(min: 100, ideal: 140)
            TableColumn("Size", value: \.size) { item in
                Text(item.isDirectory ? "—" : ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 60, ideal: 80)
            TableColumn("Kind", value: \.kind) { item in
                Text(item.kind).foregroundStyle(.secondary).lineLimit(1)
            }
            .width(min: 80, ideal: 120)
        }
        .font(.system(size: 13 * scale))
        .alternatingRowBackgrounds(striped ? .enabled : .disabled)
        .contextMenu(forSelectionType: URL.self) { urls in
            if urls.isEmpty {
                Button("New Folder") { app.newFolder() }
            } else {
                Button("Open") { pane.open(urls) }
                Divider()
                Button("Rename…") { app.beginRename(urls) }
                Button("Copy to Other Pane") { app.transfer(urls, move: false) }
                Button("Move to Other Pane") { app.transfer(urls, move: true) }
                Divider()
                Button("Move to Trash") { app.trash(urls) }
            }
        } primaryAction: { urls in
            pane.open(urls)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Text((pane.currentURL.path as NSString).abbreviatingWithTildeInPath)
                    .font(.system(size: 12 * scale))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(.bar)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if statusBar {
                HStack {
                    Spacer()
                    Text(statusText)
                        .font(.system(size: 12 * scale))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(.bar)
            }
        }
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
