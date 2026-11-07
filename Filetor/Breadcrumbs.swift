import SwiftUI

/// Clickable path above each pane, Paths style. The + at the right opens a new tab.
struct BreadcrumbBar: View {
    let pane: PaneModel
    let onNewTab: () -> Void
    @AppStorage("textSize") private var textSize = 1

    private var s: CGFloat { UIScale.value(textSize) }

    private var crumbs: [URL] {
        var list: [URL] = [URL(filePath: "/")]
        var cur = URL(filePath: "/")
        for part in pane.currentURL.standardizedFileURL.pathComponents.dropFirst() {
            cur = cur.appending(path: part)
            list.append(cur)
        }
        return list
    }

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6 * s) {
                    ForEach(Array(crumbs.enumerated()), id: \.offset) { i, url in
                        if i > 0 {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9 * s, weight: .semibold))
                                .foregroundStyle(Color.primary.opacity(0.35))
                        }
                        Button { pane.navigate(to: url) } label: {
                            HStack(spacing: 5 * s) {
                                if i == 0 {
                                    Image(systemName: "internaldrive")
                                        .font(.system(size: 12 * s))
                                        .foregroundStyle(Color.primary.opacity(0.55))
                                } else {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                        .resizable()
                                        .frame(width: 15 * s, height: 15 * s)
                                }
                                Text(i == 0 ? FileManager.default.displayName(atPath: "/") : url.lastPathComponent)
                                    .font(.system(size: 14 * s))
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
            }
            .defaultScrollAnchor(.trailing)
            Button(action: onNewTab) {
                Image(systemName: "plus")
                    .font(.system(size: 14 * s))
                    .foregroundStyle(Color.primary.opacity(0.55))
                    .frame(width: 36 * s, height: 30 * s)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("New Tab")
        }
        .frame(height: 44 * s)
    }
}
