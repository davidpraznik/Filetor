import SwiftUI

/// Clickable path above each pane, Paths style. The + at the right opens a new tab.
struct BreadcrumbBar: View {
    let pane: PaneModel
    let onNewTab: () -> Void
    @AppStorage("textSize") private var textSize = 1
    @State private var contentWidth: CGFloat = 0
    @State private var viewWidth: CGFloat = 0

    private var s: CGFloat { UIScale.value(textSize) }

    /// Shows the end of a long path, or the start when everything fits. Runs again whenever the pane is resized,
    /// so an offset from an earlier, narrower layout never sticks.
    private func align(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            if contentWidth <= viewWidth + 0.5 {
                proxy.scrollTo("start", anchor: .leading)
            } else {
                proxy.scrollTo("end", anchor: .trailing)
            }
        }
    }

    /// Mounted volume (under /Volumes) the pane is in, if any. Its crumbs start at the volume, not at the boot disk.
    private var volumeRoot: URL? {
        let parts = pane.currentURL.standardizedFileURL.pathComponents
        guard parts.count >= 3, parts[1] == "Volumes" else { return nil }
        let v = URL(filePath: "/Volumes/" + parts[2])
        // The boot disk shows up as a symlink in /Volumes; treat it as the normal root.
        if (try? v.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true { return nil }
        return v
    }

    private var rootIcon: String {
        guard let v = volumeRoot else { return "internaldrive" }
        let local = (try? v.resourceValues(forKeys: [.volumeIsLocalKey]))?.volumeIsLocal ?? true
        return local ? "externaldrive" : "externaldrive.connected.to.line.below"
    }

    private var rootName: String {
        volumeRoot?.lastPathComponent ?? FileManager.default.displayName(atPath: "/")
    }

    private var crumbs: [URL] {
        let base = volumeRoot ?? URL(filePath: "/")
        var list: [URL] = [base]
        var cur = base
        let skip = volumeRoot == nil ? 1 : 3
        for part in pane.currentURL.standardizedFileURL.pathComponents.dropFirst(skip) {
            cur = cur.appending(path: part)
            list.append(cur)
        }
        return list
    }

    var body: some View {
        HStack(spacing: 0) {
            ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                Color.clear.frame(width: 0, height: 1).id("start")
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
                                    Image(systemName: rootIcon)
                                        .font(.system(size: 12 * s))
                                        .foregroundStyle(Color.primary.opacity(0.55))
                                } else {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                        .resizable()
                                        .frame(width: 15 * s, height: 15 * s)
                                }
                                Text(i == 0 ? rootName : url.lastPathComponent)
                                    .font(.system(size: 14 * s))
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                        .id(i)
                    }
                }
                .padding(.horizontal, 14)
                Color.clear.frame(width: 0, height: 1).id("end")
                }
                .background(GeometryReader { g in
                    Color.clear.onChange(of: g.size.width, initial: true) { _, w in contentWidth = w; align(proxy) }
                })
            }
            .background(GeometryReader { g in
                Color.clear.onChange(of: g.size.width, initial: true) { _, w in viewWidth = w; align(proxy) }
            })
            // Soft fade at the left edge, so a long path that scrolls under it never ends hard against the border.
            .mask(
                HStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 24 * s)
                    Rectangle()
                }
            )
            .onChange(of: pane.currentURL) { _, _ in align(proxy) }
            }
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
