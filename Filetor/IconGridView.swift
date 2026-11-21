import SwiftUI
import QuickLookThumbnailing

/// Icon view: grid of large icons with names under them.
struct IconGridView: View {
    let pane: PaneModel
    let scale: CGFloat
    let foldersFirst: Bool
    let gridIconSize: CGFloat
    let showExtensions: Bool
    let iconPreviews: Bool
    let themed: Bool
    let tint: Int

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: max(96, gridIconSize + 44) * scale), spacing: 6)], spacing: 10) {
                ForEach(pane.sortedItems) { item in
                    let selected = pane.selection.contains(item.url)
                    VStack(spacing: 4) {
                        GridIcon(item: item, side: gridIconSize * scale, preview: iconPreviews,
                                 style: themed ? ThemedFolderIcon.style(for: item) : nil)
                        Text(item.displayName(showExtension: showExtensions))
                            .font(.system(size: 12 * scale))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .foregroundStyle(selected ? Color.white : Color.primary)
                            .padding(.horizontal, 4)
                            .background(RoundedRectangle(cornerRadius: 4).fill(selected ? Color.filetor : Color.clear))
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Color.primary.opacity(0.08) : Color.clear))
                    .contentShape(Rectangle())
                    .draggable(item.url)
                    .onTapGesture(count: 2) { pane.open([item.url]) }
                    .onTapGesture {
                        if NSEvent.modifierFlags.contains(.command) {
                            if selected { pane.selection.remove(item.url) } else { pane.selection.insert(item.url) }
                        } else {
                            pane.selection = [item.url]
                        }
                    }
                }
            }
            .padding(12)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onTapGesture { pane.selection = [] }
    }
}

/// Icon of one item in the icon view. With previews on, the file icon is replaced by a preview once it is read.
private struct GridIcon: View {
    let item: FileItem
    let side: CGFloat
    let preview: Bool
    let style: (theme: FolderTheme, link: Bool)?
    @State private var image: NSImage?

    var body: some View {
        Image(nsImage: style.map { ThemedFolderIcon.image($0.theme, side: side, glyph: true, link: $0.link) } ?? image ?? NSWorkspace.shared.icon(forFile: item.url.path))
            .resizable()
            .interpolation(.high)
            .frame(width: side, height: side)
            .task(id: "\(item.url.path)|\(Int((side / 16).rounded(.up)))|\(preview)") {
                image = nil
                guard preview, !item.isDirectory else { return }
                let step = (side / 16).rounded(.up) * 16
                let request = QLThumbnailGenerator.Request(
                    fileAt: item.url,
                    size: CGSize(width: step, height: step),
                    scale: NSScreen.main?.backingScaleFactor ?? 2,
                    representationTypes: .thumbnail
                )
                if let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
                    image = rep.nsImage
                }
            }
    }
}
