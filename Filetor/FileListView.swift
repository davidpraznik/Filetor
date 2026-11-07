import SwiftUI

struct FileListView: View {
    @Bindable var pane: PaneModel

    var body: some View {
        Table(pane.sortedItems, selection: $pane.selection, sortOrder: $pane.sortOrder) {
            TableColumn("Name", value: \.name) { item in
                HStack(spacing: 6) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                        .resizable()
                        .frame(width: 16, height: 16)
                    Text(item.name).lineLimit(1)
                }
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
        .contextMenu(forSelectionType: URL.self) { _ in
        } primaryAction: { urls in
            pane.open(urls)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Text((pane.currentURL.path as NSString).abbreviatingWithTildeInPath)
                    .font(.callout)
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
            HStack {
                Text(statusText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(.bar)
        }
        .overlay {
            if let msg = pane.errorMessage {
                ContentUnavailableView("Cannot open folder", systemImage: "lock", description: Text(msg))
            }
        }
    }

    private var statusText: String {
        let total = pane.sortedItems.count
        let selected = pane.selection.count
        let items = total == 1 ? "1 item" : "\(total) items"
        return selected > 0 ? "\(selected) of \(items) selected" : items
    }
}
