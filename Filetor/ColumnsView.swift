import SwiftUI

/// Column view: each selected folder opens its contents in a new column to the right.
struct ColumnsView: View {
    let pane: PaneModel
    let scale: CGFloat
    /// Folders opened to the right of the first column (the first column is the pane's current folder).
    @State private var chain: [URL] = []
    @State private var picked: [Int: URL] = [:]

    private var roots: [URL] { [pane.currentURL] + chain }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(Array(roots.enumerated()), id: \.offset) { i, url in
                        ColumnList(url: url, scale: scale, showHidden: pane.showHidden, selected: picked[i]) { item in
                            choose(item, in: i)
                        } open: { item in
                            pane.open([item.url])
                        }
                        .frame(width: 240 * scale)
                        .id(i)
                        Divider()
                    }
                }
            }
            .onChange(of: roots.count) { _, n in
                withAnimation { proxy.scrollTo(n - 1, anchor: .trailing) }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onChange(of: pane.currentURL) { _, _ in chain = []; picked = [:] }
    }

    private func choose(_ item: FileItem, in column: Int) {
        chain = Array(chain.prefix(column))
        picked = picked.filter { $0.key < column }
        picked[column] = item.url
        if item.isDirectory { chain.append(item.url) }
        pane.selection = [item.url]
    }
}

private struct ColumnList: View {
    let url: URL
    let scale: CGFloat
    let showHidden: Bool
    let selected: URL?
    let onSelect: (FileItem) -> Void
    let open: (FileItem) -> Void

    private var items: [FileItem] {
        let opts: FileManager.DirectoryEnumerationOptions = showHidden ? [] : [.skipsHiddenFiles]
        let urls = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: FileItem.keys, options: opts)) ?? []
        let all = urls.map { FileItem(url: $0) }
        let sorted = all.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return sorted.filter { $0.isDirectory } + sorted.filter { !$0.isDirectory }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(items) { item in
                    let on = selected == item.url
                    HStack(spacing: 6 * scale) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                            .resizable()
                            .frame(width: 17 * scale, height: 17 * scale)
                        Text(item.name).lineLimit(1)
                        Spacer(minLength: 0)
                        if item.isDirectory {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10 * scale, weight: .semibold))
                                .foregroundStyle(on ? Color.white : Color.primary.opacity(0.4))
                        }
                    }
                    .font(.system(size: 13 * scale))
                    .foregroundStyle(on ? Color.white : Color.primary)
                    .padding(.horizontal, 8)
                    .frame(height: 24 * scale)
                    .background(on ? Color.accentColor : Color.clear)
                    .contentShape(Rectangle())
                    .draggable(item.url)
                    .onTapGesture(count: 2) { open(item) }
                    .onTapGesture { onSelect(item) }
                }
            }
        }
    }
}
