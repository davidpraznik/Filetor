import SwiftUI
import Observation

/// One thing ⌘Z can take back and ⇧⌘Z can do again. The closures return an error message, or nil when it worked.
struct SyncBatchState {
    var remaining: Int
    var parts: [(undo: () -> String?, redo: () -> String?, count: Int)] = []
}

struct UndoStep {
    let title: String
    let undo: () -> String?
    let redo: () -> String?
}

@Observable
final class PaneGroup {
    var tabs: [PaneModel] = [PaneModel()]
    var selected = 0

    var current: PaneModel { tabs[min(selected, tabs.count - 1)] }

    func newTab() {
        tabs.append(PaneModel(url: current.currentURL))
        selected = tabs.count - 1
    }

    func newTab(at url: URL) {
        tabs.append(PaneModel(url: url))
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
    var showShortcuts = false
    var focusSearch = 0
    /// True while the toolbar Search field is on screen.
    var searchFieldVisible = false
    /// Fallback filter bar under the breadcrumbs (used when the toolbar has no Search field).
    var showFilterBar = false
    var filterBarFocus = 0

    func activateSearch() {
        if searchFieldVisible { focusSearch += 1 }
        else { showFilterBar = true; filterBarFocus += 1 }
    }
    var showPalette = false
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
    /// Items waiting for the "Delete Immediately?" confirmation.
    var pendingDelete: [URL]?
    /// Result of Find Duplicates or Compare Folders.
    var report: Report?
    var sync: SyncSession?
    var renameTarget: URL?
    var renameText = ""
    /// Steps that ⌘Z can undo, and steps that ⇧⌘Z can do again (newest last).
    private(set) var undoSteps: [UndoStep] = []
    private(set) var redoSteps: [UndoStep] = []
    /// Transfers that belong to one Synchronize run; they become a single undo step.
    @ObservationIgnored var syncBatches: [UUID: SyncBatchState] = [:]
    var undoTitle: String? { undoSteps.last.map { "Undo " + $0.title } }
    var redoTitle: String? { redoSteps.last.map { "Redo " + $0.title } }

    func pushUndo(_ title: String, undo: @escaping () -> String?, redo: @escaping () -> String?) {
        undoSteps.append(UndoStep(title: title, undo: undo, redo: redo))
        if undoSteps.count > 50 { undoSteps.removeFirst() }
        redoSteps.removeAll()
    }

    private var textFieldHasFocus: Bool { NSApp.keyWindow?.firstResponder is NSTextView }

    /// ⌘Z. In a text field it undoes the typing; otherwise it takes back the last file operation.
    func undo() {
        if textFieldHasFocus {
            NSApp.sendAction(Selector(("undo:")), to: nil, from: nil)
            return
        }
        guard let step = undoSteps.popLast() else { NSSound.beep(); return }
        if let error = step.undo() { alert = error } else { redoSteps.append(step) }
        refresh()
    }

    /// ⇧⌘Z.
    func redo() {
        if textFieldHasFocus {
            NSApp.sendAction(Selector(("redo:")), to: nil, from: nil)
            return
        }
        guard let step = redoSteps.popLast() else { NSSound.beep(); return }
        if let error = step.redo() { alert = error } else { undoSteps.append(step) }
        refresh()
    }

    init() {
        transfers.onFinished = { [weak self] in self?.refresh() }
        transfers.onError = { [weak self] message in self?.alert = message }
        transfers.onCompleted = { [weak self] move, records, batch in self?.recordTransferUndo(move: move, records: records, batch: batch) }
        restoreSession()
        for name in [NSApplication.willTerminateNotification, NSApplication.didResignActiveNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.saveSession() }
            }
        }
    }

    // MARK: Session restore

    /// Saves the open folders and tabs of both panes (restored on next launch).
    func saveSession() {
        let data: [String: Any] = [
            "tabs": groups.map { $0.tabs.map { $0.currentURL.path } },
            "selected": groups.map(\.selected),
            "active": activeIndex
        ]
        UserDefaults.standard.set(data, forKey: "session")
    }

    private func restoreSession() {
        guard UserDefaults.standard.object(forKey: "restoreSession") as? Bool ?? true,
              let data = UserDefaults.standard.dictionary(forKey: "session"),
              let tabs = data["tabs"] as? [[String]],
              tabs.count == groups.count else { return }
        let selected = data["selected"] as? [Int] ?? []
        for (i, paths) in tabs.enumerated() {
            let urls = paths.map { URL(fileURLWithPath: $0, isDirectory: true) }.filter {
                var isDir: ObjCBool = false
                return FileManager.default.fileExists(atPath: $0.path, isDirectory: &isDir) && isDir.boolValue
            }
            guard !urls.isEmpty else { continue }
            groups[i].tabs = urls.map { PaneModel(url: $0) }
            let sel = i < selected.count ? selected[i] : 0
            groups[i].selected = min(max(sel, 0), urls.count - 1)
        }
        if let a = data["active"] as? Int, groups.indices.contains(a) { activeIndex = a }
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
            let steps = Self.createdSteps(url)
            pushUndo("New File", undo: steps.undo, redo: steps.redo)
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

    /// Opens Finder's Get Info window for the selection through the system "Show Info in Finder" service.
    func getInfo(_ urls: Set<URL>) {
        guard !urls.isEmpty else { return }
        let pb = NSPasteboard(name: NSPasteboard.Name("com.davidpraznik.Filetor.getinfo"))
        pb.clearContents()
        pb.writeObjects(urls.sorted { $0.path < $1.path } as [NSURL])
        if !NSPerformService("Finder/Show Info", pb) {
            alert = "Could not open Get Info in Finder."
        }
    }

    func rotateImages(_ urls: Set<URL>, degrees: Int) {
        let list = urls.sorted { $0.lastPathComponent < $1.lastPathComponent }
        Task {
            let err = await Task.detached { FileTools.rotate(list, degrees: degrees) }.value
            refresh()
            if let err { alert = err }
        }
    }

    func stripMetadata(_ urls: Set<URL>) {
        let list = urls.sorted { $0.lastPathComponent < $1.lastPathComponent }
        Task {
            let err = await Task.detached { FileTools.stripMetadata(list) }.value
            refresh()
            if let err { alert = err }
        }
    }

    func convertImages(_ urls: Set<URL>, format: String, ext: String) {
        let list = urls.sorted { $0.lastPathComponent < $1.lastPathComponent }
        Task {
            let err = await Task.detached { FileTools.convert(list, format: format, ext: ext) }.value
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

    /// Reloads every pane, for example after a setting that changes the listing.
    func reloadPanes() { refresh() }

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
            let folderURL = pane.currentURL.appending(path: name)
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: false)
            let steps = Self.createdSteps(folderURL)
            pushUndo("New Folder", undo: steps.undo, redo: steps.redo)
            refresh()
            let created = pane.items.filter { $0.name == name }.map(\.id)
            pane.selection = Set(created)
            if let url = created.first { beginRename([url]) }
        } catch {
            alert = error.localizedDescription
        }
    }

    /// Undo of a created item sends it to the Trash; redo takes it back out.
    private static func createdSteps(_ url: URL) -> (undo: () -> String?, redo: () -> String?) {
        var trashed: URL?
        let undo: () -> String? = {
            do {
                var result: NSURL?
                try FileManager.default.trashItem(at: url, resultingItemURL: &result)
                trashed = result as URL?
                return nil
            } catch { return error.localizedDescription }
        }
        let redo: () -> String? = {
            guard let t = trashed else { return "Nothing to redo." }
            do { try FileManager.default.moveItem(at: t, to: url); return nil }
            catch { return error.localizedDescription }
        }
        return (undo, redo)
    }

    func trash(_ urls: Set<URL>) {
        // Off the main thread: on a network disk trashItem can take a while before it fails, which showed the spinning wheel.
        // The toolbar progress ring only shows up when it takes longer than a moment, so quick trashing causes no flicker.
        let job = TransferJob(title: "Moving to Trash")
        Task {
            let shower = Task {
                try? await Task.sleep(for: .milliseconds(400))
                if !Task.isCancelled { transfers.jobs.append(job) }
            }
            let r = await Task.detached(priority: .userInitiated) { Self.trashAll(urls) }.value
            shower.cancel()
            transfers.jobs.removeAll { $0.id == job.id }
            finishTrash(failed: r.failed, noTrash: r.noTrash, moved: r.moved)
        }
    }

    nonisolated private static func trashAll(_ urls: Set<URL>) -> (failed: [String], noTrash: [URL], moved: [(original: URL, trashed: URL)]) {
        var failed: [String] = []
        var noTrash: [URL] = []
        var moved: [(original: URL, trashed: URL)] = []
        for url in urls {
            do {
                var result: NSURL?
                try FileManager.default.trashItem(at: url, resultingItemURL: &result)
                if let result { moved.append((original: url, trashed: result as URL)) }
            } catch {
                // Network and some external volumes have no Trash; Finder offers to delete right away.
                if (error as? CocoaError)?.code == .featureUnsupported { noTrash.append(url) }
                else { failed.append("\(url.lastPathComponent): \(error.localizedDescription)") }
            }
        }
        return (failed, noTrash, moved)
    }

    private func finishTrash(failed: [String], noTrash: [URL], moved movedItems: [(original: URL, trashed: URL)]) {
        var moved = movedItems
        if !noTrash.isEmpty { pendingDelete = noTrash.sorted { $0.path < $1.path } }
        if !moved.isEmpty {
            pushUndo(moved.count == 1 ? "Move to Trash" : "Move to Trash (\(moved.count) items)", undo: {
                var errors: [String] = []
                for m in moved {
                    if FileManager.default.fileExists(atPath: m.original.path) {
                        errors.append("\"\(m.original.lastPathComponent)\" already exists.")
                        continue
                    }
                    do { try FileManager.default.moveItem(at: m.trashed, to: m.original) }
                    catch { errors.append("\(m.original.lastPathComponent): \(error.localizedDescription)") }
                }
                return errors.isEmpty ? nil : errors.joined(separator: "\n")
            }, redo: {
                var errors: [String] = []
                for i in moved.indices {
                    do {
                        var result: NSURL?
                        try FileManager.default.trashItem(at: moved[i].original, resultingItemURL: &result)
                        if let result { moved[i].trashed = result as URL }
                    } catch { errors.append("\(moved[i].original.lastPathComponent): \(error.localizedDescription)") }
                }
                return errors.isEmpty ? nil : errors.joined(separator: "\n")
            })
        }
        refresh()
        if !failed.isEmpty { alert = failed.joined(separator: "\n") }
    }

    /// Asks first, then deletes without the Trash. This cannot be undone.
    func deleteImmediately(_ urls: Set<URL>) {
        guard !urls.isEmpty else { return }
        pendingDelete = urls.sorted { $0.path < $1.path }
    }

    func confirmDelete() {
        guard let urls = pendingDelete else { return }
        pendingDelete = nil
        // Runs in the background and shows in the toolbar progress ring like a copy.
        let job = TransferJob(title: urls.count == 1 ? "Deleting \(urls[0].lastPathComponent)" : "Deleting \(urls.count) items")
        transfers.jobs.append(job)
        Task {
            var failed: [String] = []
            for (i, url) in urls.enumerated() {
                job.currentName = url.lastPathComponent
                if let error = await Task.detached(priority: .userInitiated, operation: { Self.remove(url) }).value { failed.append(error) }
                job.fraction = Double(i + 1) / Double(urls.count)
            }
            job.isFinished = true
            refresh()
            if !failed.isEmpty { alert = failed.joined(separator: "\n") }
            try? await Task.sleep(for: .seconds(1))
            transfers.jobs.removeAll { $0.id == job.id }
        }
    }

    nonisolated private static func remove(_ url: URL) -> String? {
        do { try FileManager.default.removeItem(at: url); return nil }
        catch { return "\(url.lastPathComponent): \(error.localizedDescription)" }
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
    private static func moveViaTemps(_ moves: [(from: URL, to: URL)]) throws {
        let fm = FileManager.default
        var temps: [(tmp: URL, final: URL)] = []
        for m in moves {
            let tmp = m.from.deletingLastPathComponent().appending(path: ".filetor-\(UUID().uuidString)")
            try fm.moveItem(at: m.from, to: tmp)
            temps.append((tmp: tmp, final: m.to))
        }
        for t in temps { try fm.moveItem(at: t.tmp, to: t.final) }
    }

    func applyBatchRename(_ pairs: [(URL, String)]) {
        let moves = pairs
            .filter { $0.1 != $0.0.lastPathComponent }
            .map { (from: $0.0, to: $0.0.deletingLastPathComponent().appending(path: $0.1)) }
        do {
            try Self.moveViaTemps(moves)
            if !moves.isEmpty {
                pushUndo("Rename", undo: {
                    do { try Self.moveViaTemps(moves.map { (from: $0.to, to: $0.from) }); return nil }
                    catch { return error.localizedDescription }
                }, redo: {
                    do { try Self.moveViaTemps(moves); return nil }
                    catch { return error.localizedDescription }
                })
            }
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
            pushUndo("Rename", undo: {
                if FileManager.default.fileExists(atPath: url.path) { return "\"\(url.lastPathComponent)\" already exists." }
                do { try FileManager.default.moveItem(at: dest, to: url); return nil }
                catch { return error.localizedDescription }
            }, redo: {
                if FileManager.default.fileExists(atPath: dest.path) { return "\"\(dest.lastPathComponent)\" already exists." }
                do { try FileManager.default.moveItem(at: url, to: dest); return nil }
                catch { return error.localizedDescription }
            })
            refresh()
        } catch {
            alert = error.localizedDescription
        }
    }

    /// Files dropped onto a pane or folder (from the other pane, Drop Stack, Finder).
    /// Moves every pane that is inside the volume to Home, then ejects it off the main thread.
    func eject(_ volume: URL) {
        let prefix = volume.standardizedFileURL.path
        let home = URL(filePath: NSHomeDirectory())
        for g in groups {
            for t in g.tabs where t.currentURL.standardizedFileURL.path.hasPrefix(prefix) {
                t.navigate(to: home)
            }
        }
        DispatchQueue.global().async {
            try? NSWorkspace.shared.unmountAndEjectDevice(at: volume)
        }
    }

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
