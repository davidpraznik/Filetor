import SwiftUI

/// Right-hand info panel: details of the selected item, or of the current folder when nothing is selected.
struct InfoPanel: View {
    let app: AppModel
    @AppStorage("textSize") private var textSize = 1
    @State private var totalSize: Int64?

    private var s: CGFloat { UIScale.value(textSize) }

    var body: some View {
        let pane = app.active
        let urls = pane.selection.sorted { $0.path < $1.path }
        ScrollView {
            VStack(alignment: .leading, spacing: 14 * s) {
                if urls.count > 1 {
                    multiple(urls)
                } else {
                    single(urls.first ?? pane.currentURL, isFolderView: urls.isEmpty)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 270 * s)
        .background(Color.primary.opacity(0.025))
        .task(id: urls + [pane.currentURL]) {
            totalSize = nil
            let list = urls.isEmpty ? [pane.currentURL] : urls
            totalSize = await Task.detached(priority: .userInitiated) {
                list.map { FileTools.size(of: $0) }.reduce(0, +)
            }.value
        }
    }

    private func single(_ url: URL, isFolderView: Bool) -> some View {
        let item = FileItem(url: url)
        return VStack(alignment: .leading, spacing: 14 * s) {
            HStack {
                Spacer()
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 84 * s, height: 84 * s)
                Spacer()
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(url.lastPathComponent.isEmpty ? "/" : url.lastPathComponent)
                    .font(.system(size: 15 * s, weight: .semibold))
                    .textSelection(.enabled)
                if isFolderView {
                    Text("Current folder").foregroundStyle(.secondary)
                }
            }
            Divider()
            row("Kind", item.kind)
            row("Size", sizeText)
            row("Where", url.deletingLastPathComponent().path)
            Divider()
            row("Created", date(item.created))
            row("Modified", date(item.modified))
            row("Last opened", date(item.lastOpened))
        }
        .font(.system(size: 12.5 * s))
    }

    private func multiple(_ urls: [URL]) -> some View {
        VStack(alignment: .leading, spacing: 14 * s) {
            Text("\(urls.count) items selected")
                .font(.system(size: 15 * s, weight: .semibold))
            Divider()
            row("Total size", sizeText)
        }
        .font(.system(size: 12.5 * s))
    }

    private var sizeText: String {
        guard let totalSize else { return "Calculating…" }
        return ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }

    private func date(_ d: Date) -> String {
        d == .distantPast ? "--" : d.formatted(date: .abbreviated, time: .shortened)
    }

    private func row(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 11 * s)).foregroundStyle(Color.primary.opacity(0.45))
            Text(value).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
    }
}
