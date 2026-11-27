import SwiftUI
import AppKit

/// One popup for ⇧⌘G and Connect to Server: a path opens a folder (or a file's folder with the file selected),
/// an address such as smb://server/share connects to the server.
struct GoToFolderPopup: View {
    let app: AppModel
    @State private var text = ""
    @State private var initialText = ""
    @State private var index = 0
    @State private var message: String?
    @State private var waiting = false
    @FocusState private var focused: Bool
    @AppStorage("textSize") private var textSize = 1
    @AppStorage("recentServers") private var recentServersRaw = ""
    @AppStorage("recentFolders") private var recentFoldersRaw = ""
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var s: CGFloat { UIScale.value(textSize) }

    private enum Action {
        case folder(URL)
        case connect(String)
    }

    private struct Row: Identifiable {
        let id: String
        let icon: String
        let tinted: Bool
        let title: String
        let kind: String
        let action: Action
        /// Text that Tab puts in the field.
        let completion: String?
    }

    private struct Entry: Identifiable {
        let url: URL
        let isFolder: Bool
        var id: URL { url }
    }

    // MARK: Typed text

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The text starts with `scheme://`: it is a server address, not a path.
    private var hasScheme: Bool {
        trimmed.range(of: "^[A-Za-z][A-Za-z0-9+.-]*://", options: .regularExpression) != nil
    }

    /// A complete address (scheme and host), or nil while it is still being typed.
    private var serverAddress: String? {
        guard hasScheme, let url = URL(string: trimmed), let host = url.host, !host.isEmpty else { return nil }
        return trimmed
    }

    /// Nothing typed yet: the recent list and the guide are shown.
    private var untouched: Bool { text == initialText || trimmed.isEmpty }

    /// The typed text as a path: quotes removed, ~ expanded.
    private var typedPath: String {
        var t = trimmed
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

    private var recentServers: [String] { recentServersRaw.split(separator: "\n").map(String.init) }
    private var recentFolders: [String] { recentFoldersRaw.split(separator: "\n").map(String.init) }

    private func abbreviated(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }

    /// `host/share` instead of `smb://host/share`.
    private func serverTitle(_ address: String) -> String {
        guard let url = URL(string: address), let host = url.host else { return address }
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return path.isEmpty ? host : "\(host)/\(path)"
    }

    private func serverRow(_ address: String) -> Row {
        Row(id: "server:" + address, icon: "desktopcomputer", tinted: true, title: serverTitle(address),
            kind: "Server", action: .connect(address), completion: address)
    }

    // MARK: Rows

    private var rows: [Row] {
        if hasScheme {
            var out: [Row] = []
            if let address = serverAddress {
                out.append(Row(id: "connect:" + address, icon: "link", tinted: true, title: "Connect to \(serverTitle(address))",
                               kind: "Server", action: .connect(address), completion: nil))
            }
            let q = trimmed.lowercased()
            for r in recentServers where r != serverAddress && r.lowercased().contains(q) {
                out.append(serverRow(r))
                if out.count >= 4 { break }
            }
            return out
        }
        if untouched {
            var out: [Row] = []
            for p in recentFolders.prefix(3) {
                let url = URL(fileURLWithPath: p)
                out.append(Row(id: "folder:" + p, icon: "folder.fill", tinted: true, title: abbreviated(p), kind: "Folder",
                               action: .folder(url), completion: abbreviated(p) + "/"))
            }
            for r in recentServers.prefix(3) { out.append(serverRow(r)) }
            return out
        }
        return entries.map { e in
            Row(id: "entry:" + e.url.path, icon: e.isFolder ? "folder.fill" : "doc", tinted: e.isFolder,
                title: e.url.lastPathComponent, kind: e.isFolder ? "Folder" : "File",
                action: .folder(e.url), completion: abbreviated(e.url.path) + (e.isFolder ? "/" : ""))
        }
    }

    // MARK: Actions

    private func close() { app.showGoTo = false }

    private func remember(_ list: String, adding value: String) -> String {
        var items = list.split(separator: "\n").map(String.init).filter { $0 != value }
        items.insert(value, at: 0)
        return items.prefix(5).joined(separator: "\n")
    }

    private func go(to url: URL) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            message = "Not found"
            return
        }
        let pane = app.active
        if isDirectory.boolValue {
            recentFoldersRaw = remember(recentFoldersRaw, adding: url.standardizedFileURL.path)
            pane.navigate(to: url)
        } else {
            pane.navigate(to: url.deletingLastPathComponent())
            pane.selection = [url.standardizedFileURL]
        }
        close()
    }

    /// Mounts the share; the popup stays open ("Connecting…") until macOS has finished or failed.
    private func connect(_ address: String) {
        guard let url = URL(string: address), url.scheme != nil else { message = "Not a server address"; return }
        recentServersRaw = remember(recentServersRaw, adding: address)
        waiting = true
        app.network.connect(address: url)
    }

    private func run(_ action: Action) {
        switch action {
        case .folder(let url): go(to: url)
        case .connect(let address): connect(address)
        }
    }

    private func submit(_ list: [Row]) {
        if waiting { return }
        if hasScheme {
            if let address = serverAddress { connect(address) } else { message = "Add a server name" }
            return
        }
        if trimmed.isEmpty { message = "Type a path or server address"; return }
        if untouched {
            if list.indices.contains(index) { run(list[index].action) } else { go(to: URL(fileURLWithPath: typedPath)) }
            return
        }
        let exact = URL(fileURLWithPath: typedPath)
        if !typedPath.isEmpty, FileManager.default.fileExists(atPath: exact.path) { go(to: exact); return }
        if list.indices.contains(index) { run(list[index].action); return }
        message = "Not found"
    }

    private func complete(_ list: [Row]) {
        guard list.indices.contains(index), let completion = list[index].completion else { return }
        text = completion
        index = 0
    }

    // MARK: View

    private var returnHint: String {
        if hasScheme { return "Connect" }
        if untouched { return "Go or connect" }
        return "Go"
    }

    /// Key cap, drawn like in the search popup.
    private func key(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11 * s))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.primary.opacity(0.1)))
    }

    /// Puts the text of an example into the field, with the caret at the end.
    private func insert(_ value: String) {
        text = value
        focused = true
        placeCaretAtEnd()
    }

    private func placeCaretAtEnd() {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            if let editor = NSApp.keyWindow?.firstResponder as? NSTextView {
                editor.setSelectedRange(NSRange(location: editor.string.count, length: 0))
            }
        }
    }

    private func chip(_ label: String, insert value: String) -> some View {
        Button { insert(value) } label: {
            Text(label)
                .font(.system(size: 12 * s, design: .monospaced))
                .foregroundStyle(Color.primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.07)))
        }
        .buttonStyle(.plain)
        .onHover { inside in if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
        .help("Start with \(value)")
    }

    var body: some View {
        let list = rows
        ZStack(alignment: .top) {
            Color.black.opacity(0.16)
                .ignoresSafeArea()
                .onTapGesture { close() }
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: hasScheme ? "server.rack" : "folder").foregroundStyle(.secondary)
                    TextField("Path or server address", text: $text)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16 * s))
                        .focused($focused)
                        .disabled(waiting)
                        .onSubmit { submit(list) }
                        .onKeyPress(.tab) { complete(list); return .handled }
                        .onKeyPress(.downArrow) { index = min(index + 1, max(list.count - 1, 0)); return .handled }
                        .onKeyPress(.upArrow) { index = max(index - 1, 0); return .handled }
                        .onChange(of: text) { _, _ in index = 0; message = nil }
                    if !waiting {
                        if untouched {
                            Text("esc")
                                .font(.system(size: 11 * s))
                                .foregroundStyle(Color.primary.opacity(0.55))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
                                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.1)))
                        } else {
                            Button { text = ""; focused = true } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Clear the field and show recent folders and servers")
                        }
                    }
                    if waiting {
                        ProgressView().controlSize(.small)
                        Text("Connecting…").font(.system(size: 12 * s)).foregroundStyle(.secondary)
                    } else if let message {
                        Text(message).font(.system(size: 12 * s)).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 18)
                .frame(height: 56 * s)
                if !waiting, !list.isEmpty {
                    Divider()
                    if untouched {
                        Text("Recent")
                            .font(.system(size: 12 * s))
                            .foregroundStyle(Color.primary.opacity(0.45))
                            .padding(.horizontal, 18)
                            .padding(.top, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    VStack(spacing: 0) {
                        ForEach(Array(list.enumerated()), id: \.element.id) { i, row in
                            HStack(spacing: 12) {
                                Image(systemName: row.icon)
                                    .foregroundStyle(row.tinted ? AnyShapeStyle(Color.filetor) : AnyShapeStyle(.secondary))
                                    .frame(width: 20 * s)
                                Text(row.title).lineLimit(1)
                                Spacer(minLength: 12)
                                Text(row.kind).font(.system(size: 12 * s)).foregroundStyle(.secondary)
                            }
                            .font(.system(size: 14 * s))
                            .padding(.horizontal, 18)
                            .frame(height: 38 * s)
                            .background(RoundedRectangle(cornerRadius: 8).fill(i == index ? Color.filetor.opacity(0.14) : Color.clear))
                            .padding(.horizontal, 8)
                            .contentShape(Rectangle())
                            .onTapGesture { run(row.action) }
                        }
                    }
                    .padding(.vertical, 6)
                }
                if !waiting {
                    Divider()
                    VStack(alignment: .leading, spacing: 6 * s) {
                        HStack(spacing: 8) {
                            chip("/Volumes/", insert: "/Volumes/")
                            chip("~/", insert: "~/")
                            Text("open a folder")
                        }
                        HStack(spacing: 8) {
                            chip("smb://", insert: "smb://")
                            Text("connects to a server, for example smb://nas.local/media")
                        }
                        HStack(spacing: 8) {
                            chip("afp://", insert: "afp://")
                            chip("nfs://", insert: "nfs://")
                            chip("https://", insert: "https://")
                            Text("also work (https:// is WebDAV)")
                        }
                    }
                    .font(.system(size: 12 * s))
                    .foregroundStyle(Color.primary.opacity(0.55))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10 * s)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Divider()
                HStack(spacing: 18) {
                    if waiting {
                        HStack(spacing: 6) { key("esc"); Text("Close") }
                    } else {
                        HStack(spacing: 6) { key("↩"); Text(returnHint) }
                        if !hasScheme { HStack(spacing: 6) { key("tab"); Text("Complete") } }
                        HStack(spacing: 6) { key("esc"); Text("Close") }
                    }
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
            let prefill = app.goToPrefill
            app.goToPrefill = nil
            initialText = prefill ?? abbreviated(app.active.currentURL.path) + "/"
            text = initialText
            focused = true
            if prefill != nil {
                // The caret goes after "smb://" instead of the whole text being selected.
                placeCaretAtEnd()
            }
            withAnimation(.easeOut(duration: 0.16)) { appeared = true }
        }
        .onChange(of: app.network.connecting) { _, name in
            if name == nil, waiting { close() }
        }
    }
}
