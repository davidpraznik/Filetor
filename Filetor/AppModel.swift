import SwiftUI
import Observation

@Observable
final class PaneGroup {
    var tabs: [PaneModel] = [PaneModel()]
    var selected = 0

    var current: PaneModel { tabs[min(selected, tabs.count - 1)] }

    func newTab() {
        tabs.append(PaneModel(url: current.currentURL))
        selected = tabs.count - 1
    }

    func close(at index: Int) {
        guard tabs.count > 1, tabs.indices.contains(index) else { return }
        tabs.remove(at: index)
        if index < selected { selected -= 1 }
        selected = min(selected, tabs.count - 1)
    }
}

@Observable
final class AppModel {
    let groups = [PaneGroup(), PaneGroup()]
    var activeIndex = 0
    var dual = UserDefaults.standard.object(forKey: "startDual") as? Bool ?? true
    let transfers = TransferManager()
    let toolbarModel = ToolbarModel()
    var sidebarVisibility: NavigationSplitViewVisibility =
        (UserDefaults.standard.object(forKey: "showSidebar") as? Bool ?? true) ? .all : .detailOnly
    var showCustomize = false
    var showSettings = false
    var showConnect = false
    let favorites = FavoritesStore()
    let network = NetworkBrowser()
    /// Files being renamed together in the batch rename dialog.
    var batchRename: [URL]?
    /// Info panel on the right (Get Info). Persisted.
    var showInfo = UserDefaults.standard.bool(forKey: "showInfoPanel") {
        didSet { UserDefaults.standard.set(showInfo, forKey: "showInfoPanel") }
    }
    let updater = UpdateChecker()
    /// Files collected in the sidebar Drop Stack.
    var dropStack: [URL] = []
    var alert: String?
    var renameTarget: URL?
    var renameText = ""

    init() {
        transfers.onFinished = { [weak self] in self?.refresh() }
        transfers.onError = { [weak self] message in self?.alert = message }
    }

    var activeGroup: PaneGroup { groups[activeIndex] }
    var active: PaneModel { activeGroup.current }

    func newTab() { activeGroup.newTab() }

    func copyPath() {
        let sel = active.selection
        let paths = sel.isEmpty
            ? [active.currentURL.path]
            : sel.map(\.path).sorted()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(paths.joined(separator: "\n"), forType: .string)
    }

    // MARK: More actions

    func openSelection() { active.open(active.selection) }

    func newFile() {
        let pane = active
        let url = FileTools.unique(pane.currentURL.appending(path: "untitled"))
        if FileManager.default.createFile(atPath: url.path, contents: nil) {
            pane.load()
            let created = pane.items.filter { $0.name == url.lastPathComponent }.map(\.id)
            pane.selection = Set(created)
            if let u = created.first { beginRename([u]) }
        } else {
            alert = "Could not create the file."
        }
    }

    func duplicate(_ urls: Set<URL>) {
        let dir = active.currentURL
        let items = urls.sorted { $0.lastPathComponent < $1.lastPathComponent }.map { (src: $0, dstDir: dir) }
        transfers.start(items: items, move: false)
    }

    func quickLook(_ urls: Set<URL>) {
        guard !urls.isEmpty else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/qlmanage")
        p.arguments = ["-p"] + urls.map(\.path).sorted()
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
    }

    func touch(_ urls: Set<URL>) {
        for url in urls {
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        }
        refresh()
    }

    func openTerminal() {
        NSWorkspace.shared.open([active.currentURL],
                                withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"),
                                configuration: NSWorkspace.OpenConfiguration())
    }

    func airDrop(_ urls: Set<URL>) {
        guard !urls.isEmpty else { return }
        NSSharingService(named: .sendViaAirDrop)?.perform(withItems: Array(urls))
    }

    func folderSize(_ urls: Set<URL>) {
        let list = urls.sorted { $0.lastPathComponent < $1.lastPathComponent }
        Task {
            let lines = await Task.detached { () -> [String] in
                list.map { "\($0.lastPathComponent): " + ByteCountFormatter.string(fromByteCount: FileTools.size(of: $0), countStyle: .file) }
            }.value
            alert = lines.joined(separator: "\n")
        }
    }

    func compress(_ urls: Set<URL>) {
        let dir = active.currentURL
        let list = urls.sorted { $0.lastPathComponent < $1.lastPathComponent }
        Task {
            let err = await Task.detached { FileTools.compress(list, in: dir) }.value
            refresh()
            if let err { alert = err }
        }
    }

    func decompress(_ urls: Set<URL>) {
        let dir = active.currentURL
        let list = urls.sorted { $0.lastPathComponent < $1.lastPathComponent }
        Task {
            let err = await Task.detached { FileTools.decompress(list, in: dir) }.value
            refresh()
            if let err { alert = err }
        }
    }

    func setHidden(_ value: Bool) {
        for g in groups {
            for t in g.tabs {
                t.showHidden = value
                t.load()
            }
        }
    }

    func swapPanes() {
        guard dual else { return }
        let a = groups[0], b = groups[1]
        let tabs = a.tabs, sel = a.selected
        a.tabs = b.tabs; a.selected = b.selected
        b.tabs = tabs; b.selected = sel
    }

    func closeTab() {
        if activeGroup.tabs.count > 1 {
            activeGroup.close(at: activeGroup.selected)
        } else {
            NSApp.keyWindow?.performClose(nil)
        }
    }

    // MARK: File operations (first version, runs on the main thread)

    private func refresh() {
        for g in groups { g.current.load() }
    }

    private func sourceIndex(for urls: Set<URL>) -> Int {
        guard let first = urls.first else { return activeIndex }
        let parent = first.deletingLastPathComponent().standardizedFileURL.path
        if groups[activeIndex].current.currentURL.standardizedFileURL.path == parent { return activeIndex }
        return groups.firstIndex { $0.current.currentURL.standardizedFileURL.path == parent } ?? activeIndex
    }

    func newFolder() {
        let pane = active
        var name = "Untitled Folder"
        var n = 2
        while FileManager.default.fileExists(atPath: pane.currentURL.appending(path: name).path) {
            name = "Untitled Folder \(n)"
            n += 1
        }
        do {
            try FileManager.default.createDirectory(at: pane.currentURL.appending(path: name),
                                                    withIntermediateDirectories: false)
            refresh()
            let created = pane.items.filter { $0.name == name }.map(\.id)
            pane.selection = Set(created)
            if let url = created.first { beginRename([url]) }
        } catch {
            alert = error.localizedDescription
        }
    }

    func trash(_ urls: Set<URL>) {
        var failed: [String] = []
        for url in urls {
            do { try FileManager.default.trashItem(at: url, resultingItemURL: nil) }
            catch { failed.append("\(url.lastPathComponent): \(error.localizedDescription)") }
        }
        refresh()
        if !failed.isEmpty { alert = failed.joined(separator: "\n") }
    }

    func beginRename(_ urls: Set<URL>) {
        if urls.count > 1 {
            batchRename = urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            return
        }
        guard let url = urls.first else { return }
        renameText = url.lastPathComponent
        renameTarget = url
    }

    /// Renames in two steps through temporary names, so swaps and shifted numbering never collide.
    func applyBatchRename(_ pairs: [(URL, String)]) {
        let fm = FileManager.default
        var temps: [(URL, URL)] = []
        do {
            for (url, name) in pairs where name != url.lastPathComponent {
                let tmp = url.deletingLastPathComponent().appending(path: ".filetor-\(UUID().uuidString)")
                try fm.moveItem(at: url, to: tmp)
                temps.append((tmp, url.deletingLastPathComponent().appending(path: name)))
            }
            for (tmp, final) in temps { try fm.moveItem(at: tmp, to: final) }
        } catch {
            alert = "Rename failed: \(error.localizedDescription)"
        }
        refresh()
    }

    func commitRename() {
        guard let url = renameTarget else { return }
        renameTarget = nil
        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != url.lastPathComponent else { return }
        guard !name.contains("/") else { alert = "A name cannot contain \"/\"."; return }
        let dest = url.deletingLastPathComponent().appending(path: name)
        if FileManager.default.fileExists(atPath: dest.path) {
            alert = "\"\(name)\" already exists."
            return
        }
        do {
            try FileManager.default.moveItem(at: url, to: dest)
            refresh()
        } catch {
            alert = error.localizedDescription
        }
    }

    /// Files dropped onto a pane or folder (from the other pane, Drop Stack, Finder).
    func dropTransfer(_ urls: [URL], into dir: URL, move: Bool) {
        let items = urls
            .filter { $0 != dir && !(move && $0.deletingLastPathComponent() == dir) }
            .map { (src: $0, dstDir: dir) }
        transfers.start(items: items, move: move)
    }

    func transfer(_ urls: Set<URL>, move: Bool) {
        guard !urls.isEmpty else { return }
        guard dual else {
            alert = "Open the second pane to copy or move between panes."
            return
        }
        let src = sourceIndex(for: urls)
        let dst = groups[1 - src].current.currentURL
        let items = urls.sorted { $0.lastPathComponent < $1.lastPathComponent }.map { (src: $0, dstDir: dst) }
        transfers.start(items: items, move: move)
    }
}

extension KeyEquivalent {
    static let f2 = KeyEquivalent(Character(UnicodeScalar(NSF2FunctionKey)!))
    static let f5 = KeyEquivalent(Character(UnicodeScalar(NSF5FunctionKey)!))
    static let f6 = KeyEquivalent(Character(UnicodeScalar(NSF6FunctionKey)!))
}
