import SwiftUI

/// Popup to type or paste a path (⇧⌘G). A folder opens in the active pane, a file opens its folder with the file selected.
struct GoToFolderPopup: View {
    let app: AppModel
    @State private var text = ""
    @State private var index = 0
    @State private var message: String?
    @FocusState private var focused: Bool
    @AppStorage("textSize") private var textSize = 1
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var s: CGFloat { UIScale.value(textSize) }

    private struct Entry: Identifiable {
        let url: URL
        let isFolder: Bool
        var id: URL { url }
    }

    /// The typed text as a path: quotes removed, ~ expanded.
    private var typedPath: String {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.count >= 2, (t.hasPrefix("\"") && t.hasSuffix("\"")) || (t.hasPrefix("'") && t.hasSuffix("'")) {
            t = String(t.dropFirst().dropLast())
        }
        return (t as NSString).expandingTildeInPath
    }

    /// Folder being typed in, and the start of the name after the last slash.
    private var split: (dir: URL, prefix: String) {
        let path = typedPath
        if path.isEmpty || path.hasSuffix("/") { return (URL(fileURLWithPath: path.isEmpty ? "/" : path), "") }
        let url = URL(fileURLWithPath: path)
        return (url.deletingLastPathComponent(), url.lastPathComponent)
    }

    private var entries: [Entry] {
        let (dir, prefix) = split
        let showHidden = prefix.hasPrefix(".")
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: showHidden ? [] : [.skipsHiddenFiles]) else { return [] }
        let list = urls
            .filter { prefix.isEmpty || $0.lastPathComponent.range(of: prefix, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil }
            .map { Entry(url: $0, isFolder: (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true) }
            .sorted { ($0.isFolder ? 0 : 1, $0.url.lastPathComponent.lowercased()) < ($1.isFolder ? 0 : 1, $1.url.lastPathComponent.lowercased()) }
        return Array(list.prefix(8))
    }

    private func abbreviated(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }

    private func close() { app.showGoTo = false }

    private func go(to url: URL) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            message = "Not found"
            return
        }
        let pane = app.active
        if isDirectory.boolValue {
            pane.navigate(to: url)
        } else {
            pane.navigate(to: url.deletingLastPathComponent())
            pane.selection = [url.standardizedFileURL]
        }
        close()
    }

    private func submit(_ list: [Entry]) {
        let exact = URL(fileURLWithPath: typedPath)
        if !typedPath.isEmpty, FileManager.default.fileExists(atPath: exact.path) { go(to: exact); return }
        if list.indices.contains(index) { go(to: list[index].url); return }
        message = "Not found"
    }

    private func complete(_ list: [Entry]) {
        guard list.indices.contains(index) else { return }
        let entry = list[index]
        text = abbreviated(entry.url.path) + (entry.isFolder ? "/" : "")
        index = 0
    }

    var body: some View {
        let list = entries
        ZStack(alignment: .top) {
            Color.black.opacity(0.16)
                .ignoresSafeArea()
                .onTapGesture { close() }
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "folder").foregroundStyle(.secondary)
                    TextField("Type or paste a path", text: $text)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16 * s))
                        .focused($focused)
                        .onSubmit { submit(list) }
                        .onKeyPress(.tab) { complete(list); return .handled }
                        .onKeyPress(.downArrow) { index = min(index + 1, max(list.count - 1, 0)); return .handled }
                        .onKeyPress(.upArrow) { index = max(index - 1, 0); return .handled }
                        .onChange(of: text) { _, _ in index = 0; message = nil }
                    if let message {
                        Text(message).font(.system(size: 12 * s)).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 18)
                .frame(height: 56 * s)
                if !list.isEmpty {
                    Divider()
                    VStack(spacing: 0) {
                        ForEach(Array(list.enumerated()), id: \.element.id) { i, entry in
                            HStack(spacing: 12) {
                                Image(systemName: entry.isFolder ? "folder.fill" : "doc")
                                    .foregroundStyle(entry.isFolder ? AnyShapeStyle(Color.filetor) : AnyShapeStyle(.secondary))
                                    .frame(width: 20 * s)
                                Text(entry.url.lastPathComponent).lineLimit(1)
                                Spacer(minLength: 12)
                                Text(entry.isFolder ? "Folder" : "File").font(.system(size: 12 * s)).foregroundStyle(.secondary)
                            }
                            .font(.system(size: 14 * s))
                            .padding(.horizontal, 18)
                            .frame(height: 38 * s)
                            .background(RoundedRectangle(cornerRadius: 8).fill(i == index ? Color.filetor.opacity(0.14) : Color.clear))
                            .padding(.horizontal, 8)
                            .contentShape(Rectangle())
                            .onTapGesture { go(to: entry.url) }
                        }
                    }
                    .padding(.vertical, 6)
                }
                Divider()
                HStack(spacing: 18) {
                    Text("Return to go")
                    Text("Tab to complete")
                    Text("Esc to close")
                    Spacer(minLength: 0)
                }
                .font(.system(size: 12 * s))
                .foregroundStyle(Color.primary.opacity(0.5))
                .padding(.horizontal, 18)
                .frame(height: 36 * s)
                .background(Color.primary.opacity(0.03))
            }
            .frame(width: 560 * s)
            .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.primary.opacity(0.12)))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.3), radius: 24, y: 10)
            .scaleEffect(reduceMotion || appeared ? 1 : 0.97, anchor: .top)
            .padding(.top, 92)
        }
        .onAppear {
            text = abbreviated(app.active.currentURL.path) + "/"
            focused = true
            withAnimation(.easeOut(duration: 0.16)) { appeared = true }
        }
    }
}
