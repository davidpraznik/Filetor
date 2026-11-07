import SwiftUI

/// Icon view: grid of large icons with names under them.
struct IconGridView: View {
    let pane: PaneModel
    let scale: CGFloat

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96 * scale), spacing: 6)], spacing: 10) {
                ForEach(pane.sortedItems) { item in
                    let selected = pane.selection.contains(item.url)
                    VStack(spacing: 4) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                            .resizable()
                            .frame(width: 52 * scale, height: 52 * scale)
                        Text(item.name)
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
