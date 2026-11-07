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
    var dual = true
    var alert: String?
    var renameTarget: URL?
    var renameText = ""

    var activeGroup: PaneGroup { groups[activeIndex] }
    var active: PaneModel { activeGroup.current }

    func newTab() { activeGroup.newTab() }

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
        guard let url = urls.first else { return }
        renameText = url.lastPathComponent
        renameTarget = url
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

    func transfer(_ urls: Set<URL>, move: Bool) {
        guard !urls.isEmpty else { return }
        guard dual else {
            alert = "Open the second pane to copy or move between panes."
            return
        }
        let src = sourceIndex(for: urls)
        let dst = groups[1 - src].current.currentURL
        var failed: [String] = []
        for url in urls {
            let target = dst.appending(path: url.lastPathComponent)
            if FileManager.default.fileExists(atPath: target.path) {
                failed.append("\(url.lastPathComponent): already exists in the destination")
                continue
            }
            do {
                if move { try FileManager.default.moveItem(at: url, to: target) }
                else { try FileManager.default.copyItem(at: url, to: target) }
            } catch {
                failed.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        refresh()
        if !failed.isEmpty {
            alert = failed.joined(separator: "\n") + "\n\nThese items were skipped. The conflict dialog (Replace, Keep Both, Merge) comes in the next step."
        }
    }
}

extension KeyEquivalent {
    static let f2 = KeyEquivalent(Character(UnicodeScalar(NSF2FunctionKey)!))
    static let f5 = KeyEquivalent(Character(UnicodeScalar(NSF5FunctionKey)!))
    static let f6 = KeyEquivalent(Character(UnicodeScalar(NSF6FunctionKey)!))
}
