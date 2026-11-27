import SwiftUI
import Observation

@Observable
final class PaneModel: Identifiable {
    let id = UUID()
    var currentURL: URL = FileManager.default.homeDirectoryForCurrentUser
    var items: [FileItem] = []
    var selection = Set<URL>()
    /// Kept between launches: the sort stays as the user last set it, in every pane and tab.
    var sortOrder: [KeyPathComparator<FileItem>] = PaneModel.savedSortOrder() {
        didSet {
            guard let first = sortOrder.first else { return }
            UserDefaults.standard.set(FileTableView.Coordinator.key(for: first), forKey: "sortKey")
            UserDefaults.standard.set(first.order == .forward, forKey: "sortAscending")
        }
    }

    private static func savedSortOrder() -> [KeyPathComparator<FileItem>] {
        let key = UserDefaults.standard.string(forKey: "sortKey") ?? "name"
        let order: SortOrder = (UserDefaults.standard.object(forKey: "sortAscending") as? Bool ?? true) ? .forward : .reverse
        switch key {
        case "modified": return [KeyPathComparator(\FileItem.modified, order: order)]
        case "created": return [KeyPathComparator(\FileItem.created, order: order)]
        case "lastOpened": return [KeyPathComparator(\FileItem.lastOpened, order: order)]
        case "added": return [KeyPathComparator(\FileItem.added, order: order)]
        case "size": return [KeyPathComparator(\FileItem.size, order: order)]
        case "kind": return [KeyPathComparator(\FileItem.kind, comparator: .localizedStandard, order: order)]
        case "folder": return [KeyPathComparator(\FileItem.folder, comparator: .localizedStandard, order: order)]
        case "tags": return [KeyPathComparator(\FileItem.tagsText, comparator: .localizedStandard, order: order)]
        default: return [KeyPathComparator(\FileItem.name, comparator: .localizedStandard, order: order)]
        }
    }
    var errorMessage: String?
    var filter = "" { didSet { filterChanged() } }
    /// Search the filter text in all subfolders instead of only filtering the current folder.
    var searchSubfolders = UserDefaults.standard.bool(forKey: "searchSubfolders") {
        didSet {
            UserDefaults.standard.set(searchSubfolders, forKey: "searchSubfolders")
            restartSearch()
        }
    }
    var searchResults: [FileItem] = []
    var searching = false
    var foldersScanned = 0
    /// Name of the tag whose files are shown (a Spotlight search over the whole Mac), nil in a normal folder.
    var tagFilter: String?
    /// Set when the list shows a saved search (tagFilter then holds its name).
    var savedSearchID: UUID?
    var tagResults: [FileItem] = []
    var tagSearching = false
    @ObservationIgnored private var tagTask: Task<Void, Never>?
    var title: String { tagFilter ?? CloudLocation.title(for: currentURL) }
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    var searchActive: Bool { tagFilter == nil && (aiQuery != nil || (searchSubfolders && !filter.isEmpty)) }
    /// A search the AI turned from a sentence into filters. Searches all subfolders of the current folder.
    var aiQuery: AIQuery? { didSet { restartSearch() } }
    var aiAsking = false
    var aiMessage: String?
    /// The sentence the AI last read, so Enter can tell whether the shown result is still current.
    var lastAsked = ""

    @ObservationIgnored private var aiTask: Task<Void, Never>?
    @ObservationIgnored private var aiDebounce: Task<Void, Never>?

    /// Typing a sentence (two or more words) asks the AI after a short pause. A single word only filters by name.
    private func filterChanged() {
        aiDebounce?.cancel()
        let aiOn = UserDefaults.standard.integer(forKey: "aiProvider") != 0
        let words = filter.split(separator: " ").count
        if aiOn && words >= 2 {
            aiDebounce = Task { [weak self] in
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                self.askAI(self.filter)
            }
        } else {
            aiTask?.cancel()
            aiAsking = false
            aiMessage = nil
            if aiQuery != nil { aiQuery = nil }
            else if searchSubfolders { restartSearch() }
        }
    }

    func askAI(_ text: String) {
        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        aiDebounce?.cancel()
        aiTask?.cancel()
        aiAsking = true
        aiMessage = nil
        lastAsked = prompt
        aiTask = Task { [weak self] in
            let result = await AIStore.interpret(prompt)
            guard !Task.isCancelled, let self else { return }
            switch result {
            case .success(let query):
                SearchHistory.record(prompt)
                self.aiQuery = query
            case .failure(let failure):
                self.aiMessage = failure.message
            }
            self.aiAsking = false
        }
    }

    func clearAI() {
        aiDebounce?.cancel()
        aiTask?.cancel()
        aiAsking = false
        aiMessage = nil
        aiQuery = nil
        filter = ""
    }
    /// 0 = list, 1 = icons, 2 = columns (columns not built yet, shows the list)
    var viewMode = 0
    var showHidden = UserDefaults.standard.bool(forKey: "showHidden")

    private var backStack: [URL] = []
    private var forwardStack: [URL] = []

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }
    var canGoUp: Bool { currentURL.path != "/" }

    var sortedItems: [FileItem] {
        let visible: [FileItem]
        if tagFilter != nil {
            visible = filter.isEmpty ? tagResults : tagResults.filter { $0.name.localizedCaseInsensitiveContains(filter) }
        } else {
            visible = searchActive ? searchResults
                : filter.isEmpty ? items : items.filter { $0.name.localizedCaseInsensitiveContains(filter) }
        }
        let top = ordered(visible)
        return treeActive && !expanded.isEmpty ? flatten(top) : top
    }

    private func ordered(_ list: [FileItem]) -> [FileItem] {
        let sorted = list.sorted(using: sortOrder)
        let foldersFirst = UserDefaults.standard.object(forKey: "foldersFirst") as? Bool ?? true
        guard foldersFirst else { return sorted }
        return sorted.filter { $0.isDirectory } + sorted.filter { !$0.isDirectory }
    }

    // MARK: Folders opened in place (list view)

    /// Folders that are open in the list. Kept while moving between folders, cleared only by closing them.
    var expanded = Set<URL>()
    private var children: [URL: [FileItem]] = [:]

    /// The tree is only used in the plain list of a folder, not in search results, tag views or filtered lists.
    var treeActive: Bool { viewMode == 0 && tagFilter == nil && !searchActive && filter.isEmpty }

    /// How deep a row is below the folder that is shown (0 = directly inside it).
    func level(of url: URL) -> Int {
        guard treeActive else { return 0 }
        return max(0, url.pathComponents.count - currentURL.pathComponents.count - 1)
    }

    private func flatten(_ list: [FileItem]) -> [FileItem] {
        var out: [FileItem] = []
        for item in list {
            out.append(item)
            if item.expandable, expanded.contains(item.url), let kids = children[item.url] {
                out += flatten(ordered(kids))
            }
        }
        return out
    }

    /// Folders whose content is still being read (a network disk can take a while). The list shows a spinner for them.
    var loading = Set<URL>()

    /// Reads a folder in the background, so a slow disk never blocks the window.
    /// The file attributes are fetched together with the names, so building the items afterwards is quick.
    private func loadChildren(_ dir: URL, showLoader: Bool) {
        if showLoader { loading.insert(dir) }
        let hidden = showHidden
        let keys = FileItem.keys
        Task { [weak self] in
            let list = await Task.detached(priority: .userInitiated) { () -> [FileItem] in
                let urls = (try? FileManager.default.contentsOfDirectory(
                    at: dir, includingPropertiesForKeys: keys, options: hidden ? [] : [.skipsHiddenFiles]
                )) ?? []
                return urls.map { FileItem(url: $0) }
            }.value
            guard let self else { return }
            self.loading.remove(dir)
            guard self.expanded.contains(dir) else { return }
            self.children[dir] = list
        }
    }

    func toggleExpanded(_ url: URL) {
        if expanded.contains(url) { collapse(url) } else { expand(url) }
    }

    func expand(_ url: URL) {
        guard treeActive else { return }
        expanded.insert(url)
        loadChildren(url, showLoader: true)
    }

    func collapse(_ url: URL) {
        let prefix = url.path + "/"
        expanded = expanded.filter { $0 != url && !$0.path.hasPrefix(prefix) }
        children = children.filter { $0.key != url && !$0.key.path.hasPrefix(prefix) }
        loading = loading.filter { $0 != url && !$0.path.hasPrefix(prefix) }
        selection = selection.filter { !$0.path.hasPrefix(prefix) }
    }

    /// Re-reads the content of the open folders that are inside the folder shown now.
    private func rebuildChildren() {
        let base = currentURL.path == "/" ? "/" : currentURL.path + "/"
        for url in expanded where url.path.hasPrefix(base) {
            // The old rows stay until the new ones are read, so the list does not flicker.
            loadChildren(url, showLoader: children[url] == nil)
        }
    }

    init(url: URL? = nil) {
        if let url { currentURL = url }
        load()
    }

    func navigate(to url: URL) {
        let target = url.standardizedFileURL
        if tagFilter != nil {
            clearTag()
            if target == currentURL { load(); return }
        }
        guard target != currentURL else { return }
        backStack.append(currentURL)
        forwardStack.removeAll()
        currentURL = target
        filter = ""
        aiQuery = nil
        aiMessage = nil
        loadInBackground()
    }

    func goBack() {
        guard let prev = backStack.popLast() else { return }
        clearTag()
        forwardStack.append(currentURL)
        currentURL = prev
        loadInBackground()
    }

    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        clearTag()
        backStack.append(currentURL)
        currentURL = next
        loadInBackground()
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

    @ObservationIgnored private var loadGeneration = 0
    /// True while a folder is being read in the background and the list has already been cleared for it.
    var isOpening = false
    @ObservationIgnored private var openingDone = true

    /// Opens the folder shown now without blocking the window: it is read off the main thread, and the old rows
    /// stay until the new ones are ready. A network disk (especially while it is busy with a copy) can take seconds.
    func loadInBackground() {
        selection.removeAll()
        loadGeneration += 1
        let generation = loadGeneration
        let dir = currentURL
        let hidden = showHidden
        // A quick folder keeps the old rows until the new ones arrive (no flicker); a slow one clears the list
        // so the old rows are not shown under the new path.
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard let self, generation == self.loadGeneration, self.currentURL == dir, !self.openingDone else { return }
            self.items = []
            self.children = [:]
            self.errorMessage = nil
            self.isOpening = true
        }
        openingDone = false
        Task { [weak self] in
            let listing = await Task.detached(priority: .userInitiated) {
                Self.readFolder(dir, hidden: hidden)
            }.value
            guard let self, generation == self.loadGeneration, self.currentURL == dir else { return }
            openingDone = true
            isOpening = false
            if let error = listing.error {
                items = []
                children = [:]
                errorMessage = error
            } else {
                items = listing.items
                rebuildChildren()
                TagStore.shared.remember(items.flatMap(\.tags))
                lastSignature = listing.signature
                errorMessage = nil
            }
            startFolderSizes()
            startWatching()
            if searchActive { restartSearch() }
        }
    }

    nonisolated private static func readFolder(_ dir: URL, hidden: Bool) -> FolderListing {
        do {
            let urls = try FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: FileItem.keys, options: hidden ? [] : [.skipsHiddenFiles]
            )
            return FolderListing(items: urls.map { FileItem(url: $0) }, signature: signature(of: urls), error: nil)
        } catch {
            return FolderListing(items: [], signature: 0, error: error.localizedDescription)
        }
    }

    /// Re-reads the folder after a change made outside the app, keeping the selection.
    private func refresh() { reload(keepSelection: true) }

    /// Re-reads the folder (and the tag view) after a change made in the app, keeping the selection.
    func reloadKeepingSelection() {
        reload(keepSelection: true)
        if tagFilter != nil { startTagQuery() }
    }

    // MARK: Tags

    /// Shows new tags on files without re-reading the folder.
    func applyTagChanges(_ map: [URL: [String]]) {
        for i in items.indices { if let t = map[items[i].url] { items[i].tags = t } }
        for key in Array(children.keys) {
            guard var list = children[key] else { continue }
            for i in list.indices { if let t = map[list[i].url] { list[i].tags = t } }
            children[key] = list
        }
        for i in searchResults.indices { if let t = map[searchResults[i].url] { searchResults[i].tags = t } }
        if tagFilter != nil {
            for i in tagResults.indices { if let t = map[tagResults[i].url] { tagResults[i].tags = t } }
        }
        if let f = tagFilter, savedSearchID == nil {
            let store = TagStore.shared
            tagResults.removeAll { item in map[item.url] != nil && !item.tags.contains { store.matches($0, f) } }
        }
        resyncSignature()
    }

    /// Takes the tag change as the new state, so the 2-second folder watcher does not reload the folder for it.
    private func resyncSignature() {
        let dir = currentURL
        let hidden = showHidden
        Task { [weak self] in
            let sig = await Task.detached(priority: .utility) { () -> Int? in
                guard let urls = try? FileManager.default.contentsOfDirectory(
                    at: dir,
                    includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .creationDateKey, .tagNamesKey],
                    options: hidden ? [] : [.skipsHiddenFiles]
                ) else { return nil }
                return Self.signature(of: urls)
            }.value
            guard let self, self.currentURL == dir, let sig else { return }
            self.lastSignature = sig
        }
    }

    func showSaved(_ search: SavedSearch) {
        savedSearchID = search.id
        tagFilter = search.name
        tagResults = []
        selection.removeAll()
        filter = ""
        startTagQuery()
    }

    func showTag(_ name: String) {
        savedSearchID = nil
        let onNetwork = (try? currentURL.resourceValues(forKeys: [.volumeIsLocalKey]))?.volumeIsLocal == false
        tagScanRoot = onNetwork ? currentURL : nil
        tagFilter = name
        tagResults = []
        selection.removeAll()
        filter = ""
        startTagQuery()
    }

    func clearTag() {
        tagTask?.cancel()
        tagFilter = nil
        savedSearchID = nil
        tagResults = []
        tagSearching = false
    }

    /// Folder to scan by hand when the tag view was opened on a network disk (Spotlight does not index those).
    @ObservationIgnored private var tagScanRoot: URL?

    private func startTagQuery() {
        tagTask?.cancel()
        guard let name = tagFilter else { return }
        tagSearching = true
        let saved = savedSearchID.flatMap { SavedSearchStore.shared.item($0) }
        let query = saved.map { $0.makeQuery() }
        let folder = saved?.folder ?? ""
        let scanRoot = saved == nil ? tagScanRoot : nil
        tagTask = Task { [weak self] in
            var urls: [URL]
            if let query { urls = await SpotlightSearch.run(query, onlyIn: folder) } else { urls = await TagQuery.run(name) }
            guard let self, !Task.isCancelled, self.tagFilter == name else { return }
            self.showTagResults(urls, finished: scanRoot == nil)
            guard let scanRoot else { return }
            let extra = await TagQuery.scan(name, root: scanRoot)
            guard !Task.isCancelled, self.tagFilter == name else { return }
            let known = Set(urls)
            urls += extra.filter { !known.contains($0) }
            self.showTagResults(urls, finished: true)
        }
    }

    private func showTagResults(_ urls: [URL], finished: Bool) {
        let home = NSHomeDirectory()
        tagResults = urls.map { url in
            var item = FileItem(url: url)
            var parent = url.deletingLastPathComponent().path
            if parent.hasPrefix(home) { parent = "~" + String(parent.dropFirst(home.count)) }
            item.folder = parent
            return item
        }
        if finished { tagSearching = false }
    }

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
            rebuildChildren()
            TagStore.shared.remember(items.flatMap(\.tags))
            lastSignature = Self.signature(of: urls)
            errorMessage = nil
            if keepSelection {
                for i in items.indices {
                    if let size = knownSizes[items[i].url] {
                        items[i].size = size
                        items[i].sizeCalculated = true
                    }
                }
                let present = Set(items.map(\.url)).union(children.values.flatMap { $0.map(\.url) })
                selection = previousSelection.filter { present.contains($0) }
            }
        } catch {
            items = []
            children = [:]
            errorMessage = error.localizedDescription
        }
        startFolderSizes()
        if !keepSelection { startWatching(); if searchActive { restartSearch() } }
    }

    // MARK: Search in subfolders

    func stopSearch() {
        searchTask?.cancel()
        searching = false
    }

    func restartSearch() {
        searchTask?.cancel()
        searchResults = []
        foldersScanned = 0
        guard searchActive else { searching = false; return }
        searching = true
        let root = currentURL.standardizedFileURL
        let query = filter
        let ai = aiQuery
        let hidden = showHidden
        let stream = AsyncStream<SearchBatch> { cont in
            let worker = Task.detached(priority: .userInitiated) {
                Self.scan(root: root, query: query, ai: ai, hidden: hidden, into: cont)
                cont.finish()
            }
            cont.onTermination = { _ in worker.cancel() }
        }
        searchTask = Task { [weak self] in
            for await batch in stream {
                guard let self, !Task.isCancelled else { return }
                let rootPath = root.path
                self.searchResults.append(contentsOf: batch.urls.map { url in
                    var item = FileItem(url: url)
                    let parent = url.deletingLastPathComponent().path
                    item.folder = parent == rootPath ? "" : String(parent.dropFirst(rootPath.count + 1))
                    return item
                })
                self.foldersScanned = batch.folders
            }
            guard !Task.isCancelled else { return }
            self?.searching = false
        }
    }

    nonisolated private static func scan(root: URL, query: String, ai: AIQuery?, hidden: Bool, into cont: AsyncStream<SearchBatch>.Continuation) {
        var options: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
        if !hidden { options.insert(.skipsHiddenFiles) }
        guard let en = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: AIQuery.resourceKeys, options: options) else { return }
        var batch: [URL] = []
        var folders = 0
        var found = 0
        var last = Date()
        while let url = en.nextObject() as? URL {
            if Task.isCancelled { return }
            let values = try? url.resourceValues(forKeys: Set(AIQuery.resourceKeys))
            if values?.isDirectory == true { folders += 1 }
            let hit: Bool
            if let ai { hit = values.map { ai.matches(url, $0) } ?? false } else { hit = url.lastPathComponent.localizedCaseInsensitiveContains(query) }
            if hit {
                batch.append(url)
                found += 1
                if found >= 5000 { break }
            }
            if Date().timeIntervalSince(last) > 0.15 {
                cont.yield(SearchBatch(urls: batch, folders: folders))
                batch = []
                last = Date()
            }
        }
        cont.yield(SearchBatch(urls: batch, folders: folders))
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
                let last = self.lastSignature
                // Read the folder off the main thread: on a network disk every file costs a round trip,
                // and a file that is being copied changes the folder every 2 seconds.
                let listing = await Task.detached(priority: .utility) { () -> FolderListing? in
                    guard let urls = try? FileManager.default.contentsOfDirectory(
                        at: dir,
                        includingPropertiesForKeys: FileItem.keys,
                        options: hidden ? [] : [.skipsHiddenFiles]
                    ) else { return nil }
                    let sig = Self.signature(of: urls)
                    guard sig != last else { return nil }
                    return FolderListing(items: urls.map { FileItem(url: $0) }, signature: sig)
                }.value
                guard !Task.isCancelled, self.currentURL == dir else { return }
                if let listing { self.applyListing(listing) }
            }
        }
    }

    /// Shows a folder that was read in the background, keeping the selection and the calculated folder sizes.
    private func applyListing(_ listing: FolderListing) {
        let previousSelection = selection
        var knownSizes: [URL: Int64] = [:]
        for item in items where item.sizeCalculated { knownSizes[item.url] = item.size }
        items = listing.items
        rebuildChildren()
        TagStore.shared.remember(items.flatMap(\.tags))
        lastSignature = listing.signature
        errorMessage = nil
        for i in items.indices {
            if let size = knownSizes[items[i].url] {
                items[i].size = size
                items[i].sizeCalculated = true
            }
        }
        let present = Set(items.map(\.url)).union(children.values.flatMap { $0.map(\.url) })
        selection = previousSelection.filter { present.contains($0) }
        startFolderSizes()
    }

    nonisolated private static func signature(of urls: [URL]) -> Int {
        var hasher = Hasher()
        for url in urls.sorted(by: { $0.path < $1.path }) {
            let v = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .creationDateKey, .tagNamesKey])
            hasher.combine(url.path)
            hasher.combine(v?.contentModificationDate)
            hasher.combine(v?.fileSize)
            hasher.combine(v?.creationDate)
            hasher.combine(v?.tagNames)
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

nonisolated struct FolderListing: Sendable {
    var items: [FileItem]
    var signature: Int
    var error: String? = nil
}

nonisolated struct SearchBatch: Sendable {
    var urls: [URL]
    var folders: Int
}
