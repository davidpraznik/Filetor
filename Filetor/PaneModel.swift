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

    func load() {
        selection.removeAll()
        do {
            let urls = try FileManager.default.contentsOfDirectory(
                at: currentURL,
                includingPropertiesForKeys: FileItem.keys,
                options: showHidden ? [] : [.skipsHiddenFiles]
            )
            items = urls.map { FileItem(url: $0) }
            errorMessage = nil
        } catch {
            items = []
            errorMessage = error.localizedDescription
        }
    }
}
