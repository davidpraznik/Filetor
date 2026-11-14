import SwiftUI
import Observation

struct ToolbarEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var kind: String
}

struct ToolDef: Identifiable {
    let id: String
    let title: String
    let symbol: String
    var needsSelection = false
    var needsDual = false
    var isOn: ((AppModel) -> Bool)? = nil
    let run: (AppModel) -> Void
}

enum ToolCatalog {
    /// Items drawn by dedicated views instead of a plain button.
    static let special: [String: (title: String, symbol: String)] = [
        "backfwd": ("Back/Forward", "chevron.left.chevron.right"),
        "title": ("Title", "textformat"),
        "search": ("Search", "magnifyingglass"),
        "view": ("View", "list.bullet"),
        "space": ("Space", "rectangle.dashed"),
        "flex": ("Flexible Space", "arrow.left.and.right"),
    ]

    static let buttons: [ToolDef] = [
        ToolDef(id: "sidebar", title: "Sidebar", symbol: "sidebar.left",
                isOn: { $0.sidebarVisibility != .detailOnly },
                run: { $0.sidebarVisibility = ($0.sidebarVisibility == .detailOnly) ? .all : .detailOnly }),
        ToolDef(id: "enclosing", title: "Enclosing Folder", symbol: "chevron.up",
                run: { $0.active.goUp() }),
        ToolDef(id: "dual", title: "Dual Browser", symbol: "rectangle.split.2x1",
                isOn: { $0.dual }, run: { $0.dual.toggle() }),
        ToolDef(id: "swap", title: "Swap Panes", symbol: "arrow.left.arrow.right", needsDual: true,
                run: { $0.swapPanes() }),
        ToolDef(id: "quickLook", title: "Quick Look", symbol: "eye", needsSelection: true,
                run: { $0.quickLook($0.active.selection) }),
        ToolDef(id: "hidden", title: "Hidden Files", symbol: "eye.slash",
                isOn: { $0.active.showHidden }, run: { $0.active.toggleHidden() }),
        ToolDef(id: "newFolder", title: "New Folder", symbol: "folder.badge.plus",
                run: { $0.newFolder() }),
        ToolDef(id: "newFile", title: "New File", symbol: "doc.badge.plus",
                run: { $0.newFile() }),
        ToolDef(id: "newTab", title: "New Tab", symbol: "plus",
                run: { $0.newTab() }),
        ToolDef(id: "open", title: "Open", symbol: "folder", needsSelection: true,
                run: { $0.openSelection() }),
        ToolDef(id: "rename", title: "Rename", symbol: "pencil", needsSelection: true,
                run: { $0.beginRename($0.active.selection) }),
        ToolDef(id: "duplicate", title: "Duplicate", symbol: "plus.square.on.square", needsSelection: true,
                run: { $0.duplicate($0.active.selection) }),
        ToolDef(id: "copy", title: "Copy", symbol: "doc.on.doc", needsSelection: true, needsDual: true,
                run: { $0.transfer($0.active.selection, move: false) }),
        ToolDef(id: "move", title: "Move", symbol: "arrow.right.doc.on.clipboard", needsSelection: true, needsDual: true,
                run: { $0.transfer($0.active.selection, move: true) }),
        ToolDef(id: "trash", title: "Move to Trash", symbol: "trash", needsSelection: true,
                run: { $0.trash($0.active.selection) }),
        ToolDef(id: "compress", title: "Compress", symbol: "arrow.down.right.and.arrow.up.left", needsSelection: true,
                run: { $0.compress($0.active.selection) }),
        ToolDef(id: "decompress", title: "Decompress", symbol: "arrow.up.left.and.arrow.down.right", needsSelection: true,
                run: { $0.decompress($0.active.selection) }),
        ToolDef(id: "stripMeta", title: "Strip Metadata", symbol: "eraser", needsSelection: true,
                run: { $0.stripMetadata($0.active.selection) }),
        ToolDef(id: "touch", title: "Touch", symbol: "clock", needsSelection: true,
                run: { $0.touch($0.active.selection) }),
        ToolDef(id: "copyPath", title: "Copy Path", symbol: "link",
                run: { $0.copyPath() }),
        ToolDef(id: "terminal", title: "Terminal", symbol: "apple.terminal",
                run: { $0.openTerminal() }),
        ToolDef(id: "reload", title: "Reload", symbol: "arrow.clockwise",
                run: { $0.active.load() }),
        ToolDef(id: "airdrop", title: "AirDrop", symbol: "airplayaudio", needsSelection: true,
                run: { $0.airDrop($0.active.selection) }),
        ToolDef(id: "info", title: "Info Panel", symbol: "info.circle",
                isOn: { $0.showInfo }, run: { $0.showInfo.toggle() }),
        ToolDef(id: "connect", title: "Connect", symbol: "globe",
                run: { $0.showConnect = true }),
        ToolDef(id: "customize", title: "Settings", symbol: "gearshape",
                run: { $0.showSettings = true }),
    ]

    static func def(_ id: String) -> ToolDef? { buttons.first { $0.id == id } }

    static func title(_ kind: String) -> String { special[kind]?.title ?? def(kind)?.title ?? kind }
    static func symbol(_ kind: String) -> String { special[kind]?.symbol ?? def(kind)?.symbol ?? "questionmark" }

    /// Order of the palette in the Customize sheet.
    static let palette: [String] = [
        "sidebar", "backfwd", "enclosing", "title", "view", "dual", "swap",
        "quickLook", "hidden", "newFolder", "newFile", "newTab",
        "open", "rename", "duplicate", "copy", "move", "trash", "compress",
        "decompress", "stripMeta", "touch", "copyPath", "terminal", "reload",
        "airdrop", "connect", "info", "customize", "search", "space", "flex",
    ]

    static let defaultKinds: [String] = [
        "sidebar", "backfwd", "title", "flex", "airdrop", "terminal", "touch", "customize", "reload",
        "newFolder", "copyPath", "connect", "swap", "view", "dual", "search",
    ]
}

@Observable
final class ToolbarModel {
    var entries: [ToolbarEntry]
    var showLabels: Bool

    private static let key = "toolbar.entries.v1"
    private static let labelsKey = "toolbar.showLabels.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([ToolbarEntry].self, from: data) {
            entries = decoded.filter { $0.kind != "folderSize" }
        } else {
            entries = ToolCatalog.defaultKinds.map { ToolbarEntry(kind: $0) }
        }
        showLabels = UserDefaults.standard.object(forKey: Self.labelsKey) as? Bool ?? true
    }

    func save() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
        UserDefaults.standard.set(showLabels, forKey: Self.labelsKey)
    }

    func restoreDefaults() {
        entries = ToolCatalog.defaultKinds.map { ToolbarEntry(kind: $0) }
        showLabels = true
        save()
    }

    func contains(_ kind: String) -> Bool { entries.contains { $0.kind == kind } }

    func toggle(_ kind: String) {
        if kind == "space" || kind == "flex" {
            entries.append(ToolbarEntry(kind: kind))
        } else if let i = entries.firstIndex(where: { $0.kind == kind }) {
            entries.remove(at: i)
        } else {
            entries.append(ToolbarEntry(kind: kind))
        }
        save()
    }

    func drop(_ payload: String, before target: UUID?) {
        var entry: ToolbarEntry
        if payload.hasPrefix("new:") {
            let kind = String(payload.dropFirst(4))
            if kind != "space" && kind != "flex" && contains(kind) { return }
            entry = ToolbarEntry(kind: kind)
        } else if payload.hasPrefix("move:"),
                  let id = UUID(uuidString: String(payload.dropFirst(5))),
                  let idx = entries.firstIndex(where: { $0.id == id }) {
            if id == target { return }
            entry = entries.remove(at: idx)
        } else {
            return
        }
        if let t = target, let ti = entries.firstIndex(where: { $0.id == t }) {
            entries.insert(entry, at: ti)
        } else {
            entries.append(entry)
        }
        save()
    }

    func removeDropped(_ payload: String) {
        guard payload.hasPrefix("move:"), let id = UUID(uuidString: String(payload.dropFirst(5))) else { return }
        entries.removeAll { $0.id == id }
        save()
    }
}
