import SwiftUI
import Observation

@Observable
final class PaneModel: Identifiable {
    let id = UUID()
    var currentURL: URL = FileManager.default.homeDirectoryForCurrentUser
    var items: [FileItem] = []
    var selection = Set<URL>()
    var sortOrder: [KeyPathComparator<FileItem>] = [
        KeyPathComparator(\FileItem.name, comparator: .localizedStandard)
    ]
    var errorMessage: String?
    var filter = ""
    /// 0 = list, 1 = icons, 2 = columns (columns not built yet, shows the list)
    var viewMode = 0
    var showHidden = UserDefaults.standard.bool(forKey: "showHidden")

    private var backStack: [URL] = []
    private var forwardStack: [URL] = []

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }
    var canGoUp: Bool { currentURL.path != "/" }

    var sortedItems: [FileItem] {
        let visible = filter.isEmpty ? items : items.filter { $0.name.localizedCaseInsensitiveContains(filter) }
        let sorted = visible.sorted(using: sortOrder)
        let foldersFirst = UserDefaults.standard.object(forKey: "foldersFirst") as? Bool ?? true
        guard foldersFirst else { return sorted }
        return sorted.filter { $0.isDirectory } + sorted.filter { !$0.isDirectory }
    }

    init(url: URL? = nil) {
        if let url { currentURL = url }
        load()
    }

    func navigate(to url: URL) {
        let target = url.standardizedFileURL
        guard target != currentURL else { return }
        backStack.append(currentURL)
        forwardStack.removeAll()
        currentURL = target
        filter = ""
        load()
    }

    func goBack() {
        guard let prev = backStack.popLast() else { return }
        forwardStack.append(currentURL)
        currentURL = prev
        load()
    }

    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(currentURL)
        currentURL = next
        load()
    }

    func goUp() {
        guard canGoUp else { return }
        navigate(to: currentURL.deletingLastPathComponent())
    }

    func open(_ urls: Set<URL>) {
        for url in urls {
            let item = FileItem(url: url)
            if item.isDirectory {
                navigate(to: url)
                return
            } else {
                NSWorkspace.shared.open(url)
            }
        }
    }

    func toggleHidden() {
        showHidden.toggle()
        load()
    }

    func load() { reload(keepSelection: false) }

    /// Re-reads the folder after a change made outside the app, keeping the selection.
    private func refresh() { reload(keepSelection: true) }

    private func reload(keepSelection: Bool) {
        let previousSelection = selection
        var knownSizes: [URL: Int64] = [:]
        if keepSelection {
            for item in items where item.sizeCalculated { knownSizes[item.url] = item.size }
        } else {
            selection.removeAll()
        }
        do {
            let urls = try FileManager.default.contentsOfDirectory(
                at: currentURL,
                includingPropertiesForKeys: FileItem.keys,
                options: showHidden ? [] : [.skipsHiddenFiles]
            )
            items = urls.map { FileItem(url: $0) }
            lastSignature = Self.signature(of: urls)
            errorMessage = nil
            if keepSelection {
                for i in items.indices {
                    if let size = knownSizes[items[i].url] {
                        items[i].size = size
                        items[i].sizeCalculated = true
                    }
                }
                let present = Set(items.map(\.url))
                selection = previousSelection.filter { present.contains($0) }
            }
        } catch {
            items = []
            errorMessage = error.localizedDescription
        }
        startFolderSizes()
        if !keepSelection { startWatching() }
    }

    // MARK: Watching the folder for changes made outside the app

    @ObservationIgnored private var watchTask: Task<Void, Never>?
    @ObservationIgnored private var lastSignature = 0

    /// Checks the current folder every 2 seconds (only while the app is active) and reloads it when a name,
    /// size, modified date or created date has changed.
    private func startWatching() {
        watchTask?.cancel()
        let dir = currentURL
        watchTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self, !Task.isCancelled, self.currentURL == dir else { return }
                guard NSApplication.shared.isActive else { continue }
                let hidden = self.showHidden
                let sig = await Task.detached(priority: .utility) { () -> Int? in
                    guard let urls = try? FileManager.default.contentsOfDirectory(
                        at: dir,
                        includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .creationDateKey],
                        options: hidden ? [] : [.skipsHiddenFiles]
                    ) else { return nil }
                    return Self.signature(of: urls)
                }.value
                guard !Task.isCancelled, self.currentURL == dir else { return }
                if let sig, sig != self.lastSignature { self.refresh() }
            }
        }
    }

    nonisolated private static func signature(of urls: [URL]) -> Int {
        var hasher = Hasher()
        for url in urls.sorted(by: { $0.path < $1.path }) {
            let v = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .creationDateKey])
            hasher.combine(url.path)
            hasher.combine(v?.contentModificationDate)
            hasher.combine(v?.fileSize)
            hasher.combine(v?.creationDate)
        }
        return hasher.finalize()
    }

    @ObservationIgnored private var sizeTask: Task<Void, Never>?

    /// Calculates the total size of every folder in the background when "Calculate all folder sizes" is on.
    private func startFolderSizes() {
        sizeTask?.cancel()
        guard UserDefaults.standard.bool(forKey: "calculateFolderSizes") else { return }
        let folders = items.filter(\.isDirectory).map(\.url)
        guard !folders.isEmpty else { return }
        let dir = currentURL
        sizeTask = Task { [weak self] in
            for url in folders {
                if Task.isCancelled { return }
                let size = await Task.detached(priority: .utility) { FileTools.size(of: url) }.value
                if Task.isCancelled { return }
                guard let self, self.currentURL == dir,
                      let i = self.items.firstIndex(where: { $0.url == url }) else { continue }
                self.items[i].size = size
                self.items[i].sizeCalculated = true
            }
        }
    }
}
