import SwiftUI
import AppKit
import Quartz

/// AppKit file list: flat full-width stripes that run to the bottom, right-aligned Size column and header.
struct FileTableView: NSViewRepresentable {
    let pane: PaneModel
    let app: AppModel
    let items: [FileItem]
    let selection: Set<URL>
    let sortOrder: [KeyPathComparator<FileItem>]
    let scale: CGFloat
    let striped: Bool
    let compact: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let c = context.coordinator
        let table = QLTableView()
        table.qlSource = c
        table.style = .plain
        table.allowsMultipleSelection = true
        table.allowsColumnReordering = false
        table.columnAutoresizingStyle = .noColumnAutoresizing
        table.intercellSpacing = NSSize(width: 0, height: 0)
        table.gridStyleMask = []
        table.dataSource = c
        table.delegate = c
        table.target = c
        table.doubleAction = #selector(Coordinator.doubleClicked)
        table.registerForDraggedTypes([.fileURL])
        table.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
        table.setDraggingSourceOperationMask(.copy, forLocal: false)

        func add(_ id: String, _ title: String, _ width: CGFloat, min: CGFloat, right: Bool = false) {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            col.title = title
            col.width = width
            col.minWidth = min
            col.sortDescriptorPrototype = NSSortDescriptor(key: id, ascending: true)
            col.headerCell.alignment = right ? .right : .left
            table.addTableColumn(col)
        }
        add("name", "Name", 320, min: 140)
        add("modified", "Date Modified", 150, min: 100)
        add("created", "Date Created", 150, min: 100)
        add("lastOpened", "Date Last Opened", 160, min: 100)
        add("added", "Date Added", 150, min: 100)
        add("kind", "Kind", 130, min: 80)
        add("size", "Size", 90, min: 60, right: true)
        let visible = Coordinator.visibleColumns()
        for col in table.tableColumns { col.isHidden = col.identifier.rawValue != "name" && !visible.contains(col.identifier.rawValue) }
        table.allowsColumnResizing = true
        for col in table.tableColumns { col.resizingMask = .userResizingMask }
        table.tableColumns[0].resizingMask = [.autoresizingMask, .userResizingMask]

        let menu = NSMenu()
        menu.delegate = c
        table.menu = menu
        let headerMenu = NSMenu()
        headerMenu.delegate = c
        table.headerView?.menu = headerMenu
        c.headerMenu = headerMenu

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        c.table = table
        // Columns can be widened freely (the list scrolls sideways); Name fills any leftover width.
        scroll.contentView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(c, selector: #selector(Coordinator.fillWidth), name: NSView.frameDidChangeNotification, object: scroll.contentView)
        DispatchQueue.main.async { c.fillWidth() }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let c = context.coordinator
        c.parent = self
        guard let table = c.table else { return }

        let settings = [scale, striped ? 1 : 0, compact ? 1 : 0]
        let settingsChanged = settings != c.lastSettings
        let itemsChanged = items != c.items
        c.lastSettings = settings
        c.items = items

        table.usesAlternatingRowBackgroundColors = striped
        table.rowHeight = (compact ? 20 : 25) * scale

        c.syncing = true
        if let first = sortOrder.first {
            let key = Coordinator.key(for: first)
            let asc = first.order == .forward
            if table.sortDescriptors.first?.key != key || table.sortDescriptors.first?.ascending != asc {
                table.sortDescriptors = [NSSortDescriptor(key: key, ascending: asc)]
            }
        }
        if itemsChanged || settingsChanged { table.reloadData() }
        let rows = IndexSet(items.indices.filter { selection.contains(items[$0].url) })
        if table.selectedRowIndexes != rows { table.selectRowIndexes(rows, byExtendingSelection: false) }
        c.syncing = false
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
        var parent: FileTableView
        weak var table: NSTableView?
        var items: [FileItem] = []
        var lastSettings: [CGFloat] = []
        var syncing = false

        @objc func fillWidth() {
            guard let table, let clip = table.enclosingScrollView?.contentView,
                  let name = table.tableColumns.first(where: { $0.identifier.rawValue == "name" }) else { return }
            let others = table.tableColumns.filter { $0 !== name && !$0.isHidden }.reduce(CGFloat(0)) { $0 + $1.width }
            let spacing = table.intercellSpacing.width * CGFloat(table.numberOfColumns)
            name.width = max(name.minWidth, clip.bounds.width - others - spacing)
        }
        var headerMenu: NSMenu?

        static let optionalColumns: [(id: String, title: String)] = [
            ("modified", "Date Modified"), ("created", "Date Created"), ("lastOpened", "Date Last Opened"),
            ("added", "Date Added"), ("size", "Size"), ("kind", "Kind"),
        ]

        static func visibleColumns() -> Set<String> {
            if let saved = UserDefaults.standard.array(forKey: "fileColumns") as? [String] { return Set(saved) }
            return ["modified", "kind", "size"]
        }

        init(_ parent: FileTableView) { self.parent = parent }

        static func key(for c: KeyPathComparator<FileItem>) -> String {
            if c.keyPath == \FileItem.modified as PartialKeyPath<FileItem> { return "modified" }
            if c.keyPath == \FileItem.created as PartialKeyPath<FileItem> { return "created" }
            if c.keyPath == \FileItem.lastOpened as PartialKeyPath<FileItem> { return "lastOpened" }
            if c.keyPath == \FileItem.added as PartialKeyPath<FileItem> { return "added" }
            if c.keyPath == \FileItem.size as PartialKeyPath<FileItem> { return "size" }
            if c.keyPath == \FileItem.kind as PartialKeyPath<FileItem> { return "kind" }
            return "name"
        }

        func numberOfRows(in tableView: NSTableView) -> Int { items.count }

        // MARK: Copy / paste files (⌘C, ⌘V) and Return to rename

        func copySelection() {
            let urls = previewURLs
            guard !urls.isEmpty else { return }
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.writeObjects(urls as [NSURL])
        }

        func pasteHere() {
            let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self],
                                                        options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
            guard !urls.isEmpty else { return }
            parent.app.dropTransfer(urls, into: parent.pane.currentURL, move: false)
        }

        func renameSelection() {
            let urls = Set(previewURLs)
            if !urls.isEmpty { parent.app.beginRename(urls) }
        }

        // MARK: Quick Look (space bar)

        private var previewURLs: [URL] {
            guard let table else { return [] }
            return table.selectedRowIndexes.compactMap { $0 < items.count ? items[$0].url : nil }
        }

        func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { previewURLs.count }

        func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
            let urls = previewURLs
            return index < urls.count ? urls[index] as NSURL : nil
        }

        /// Lets files be dragged out of the list (Drop Stack, Finder, other apps).
        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
            guard row < items.count else { return nil }
            return items[row].url as NSURL
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let col = tableColumn, row < items.count else { return nil }
            let item = items[row]
            let s = parent.scale
            let font = NSFont.systemFont(ofSize: 13 * s)
            let id = col.identifier

            let cell = NSTableCellView()
            let text = NSTextField(labelWithString: "")
            text.font = font
            text.lineBreakMode = .byTruncatingTail
            text.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(text)
            cell.textField = text

            switch id.rawValue {
            case "name":
                let icon = NSImageView()
                icon.image = NSWorkspace.shared.icon(forFile: item.url.path)
                icon.translatesAutoresizingMaskIntoConstraints = false
                cell.addSubview(icon)
                cell.imageView = icon
                text.stringValue = item.name
                NSLayoutConstraint.activate([
                    icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
                    icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    icon.widthAnchor.constraint(equalToConstant: 17 * s),
                    icon.heightAnchor.constraint(equalToConstant: 17 * s),
                    text.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
                    text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                    text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                ])
            case "size":
                text.stringValue = item.isDirectory ? "--" : ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file)
                text.textColor = .secondaryLabelColor
                text.alignment = .right
                pin(text, in: cell)
            case "modified", "created", "lastOpened", "added":
                let d = id.rawValue == "modified" ? item.modified : id.rawValue == "created" ? item.created
                    : id.rawValue == "added" ? item.added : item.lastOpened
                text.stringValue = d == .distantPast ? "--" : Self.dateString(d)
                text.textColor = .secondaryLabelColor
                pin(text, in: cell)
            default:
                text.stringValue = item.kind
                text.textColor = .secondaryLabelColor
                pin(text, in: cell)
            }
            return cell
        }

        private func pin(_ text: NSTextField, in cell: NSView) {
            NSLayoutConstraint.activate([
                text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
                text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
        }

        private static func dateString(_ d: Date) -> String {
            let cal = Calendar.current
            let time = d.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute())
            if cal.isDateInToday(d) { return "Today, " + time }
            if cal.isDateInYesterday(d) { return "Yesterday, " + time }
            return d.formatted(.dateTime.day().month(.abbreviated).year())
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !syncing, let table else { return }
            let urls = Set(table.selectedRowIndexes.compactMap { $0 < items.count ? items[$0].url : nil })
            parent.pane.selection = urls
            if QLPreviewPanel.sharedPreviewPanelExists(), QLPreviewPanel.shared().isVisible {
                QLPreviewPanel.shared().reloadData()
            }
        }

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard !syncing, let d = tableView.sortDescriptors.first, let key = d.key else { return }
            let order: SortOrder = d.ascending ? .forward : .reverse
            let comparator: KeyPathComparator<FileItem>
            switch key {
            case "modified": comparator = KeyPathComparator(\FileItem.modified, order: order)
            case "created": comparator = KeyPathComparator(\FileItem.created, order: order)
            case "lastOpened": comparator = KeyPathComparator(\FileItem.lastOpened, order: order)
            case "added": comparator = KeyPathComparator(\FileItem.added, order: order)
            case "size": comparator = KeyPathComparator(\FileItem.size, order: order)
            case "kind": comparator = KeyPathComparator(\FileItem.kind, comparator: .localizedStandard, order: order)
            default: comparator = KeyPathComparator(\FileItem.name, comparator: .localizedStandard, order: order)
            }
            parent.pane.sortOrder = [comparator]
        }

        // MARK: Drop onto the list (copy; hold ⌘ to move). Dropping on a folder row targets that folder.

        func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int,
                       proposedDropOperation op: NSTableView.DropOperation) -> NSDragOperation {
            if op == .on, row >= 0, row < items.count, items[row].isDirectory {
                return NSEvent.modifierFlags.contains(.command) ? .move : .copy
            }
            tableView.setDropRow(-1, dropOperation: .on)
            return NSEvent.modifierFlags.contains(.command) ? .move : .copy
        }

        func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int,
                       dropOperation op: NSTableView.DropOperation) -> Bool {
            let objs = info.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                           options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
            guard !objs.isEmpty else { return false }
            let dest = (op == .on && row >= 0 && row < items.count && items[row].isDirectory)
                ? items[row].url : parent.pane.currentURL
            parent.app.dropTransfer(objs, into: dest, move: NSEvent.modifierFlags.contains(.command))
            return true
        }

        @objc func doubleClicked() {
            guard let table, table.clickedRow >= 0, table.clickedRow < items.count else { return }
            parent.pane.open([items[table.clickedRow].url])
        }

        // MARK: Context menu

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let table else { return }
            if menu === headerMenu {
                let visible = Self.visibleColumns()
                for col in Self.optionalColumns {
                    let mi = NSMenuItem(title: col.title, action: #selector(toggleColumn(_:)), keyEquivalent: "")
                    mi.target = self
                    mi.representedObject = col.id
                    mi.state = visible.contains(col.id) ? .on : .off
                    menu.addItem(mi)
                }
                return
            }
            let row = table.clickedRow
            if row >= 0, row < items.count, !table.selectedRowIndexes.contains(row) {
                table.selectRowIndexes([row], byExtendingSelection: false)
            }
            if row < 0 {
                menu.addItem(item("New Folder") { [weak self] in self?.parent.app.newFolder() })
                return
            }
            let urls = Set(table.selectedRowIndexes.compactMap { $0 < items.count ? items[$0].url : nil })
            menu.addItem(item("Open") { [weak self] in self?.parent.pane.open(urls) })
            let apps = parent.app.openApps(for: urls)
            if !apps.isEmpty {
                let with = NSMenuItem(title: "Open With", action: nil, keyEquivalent: "")
                let sub = NSMenu()
                for appURL in apps {
                    let mi = item(FileManager.default.displayName(atPath: appURL.path)) { [weak self] in
                        self?.parent.app.open(urls, with: appURL)
                    }
                    let icon = NSWorkspace.shared.icon(forFile: appURL.path)
                    icon.size = NSSize(width: 16, height: 16)
                    mi.image = icon
                    sub.addItem(mi)
                }
                with.submenu = sub
                menu.addItem(with)
            }
            menu.addItem(.separator())
            menu.addItem(item("Rename…") { [weak self] in self?.parent.app.beginRename(urls) })
            menu.addItem(item("Copy to Other Pane") { [weak self] in self?.parent.app.transfer(urls, move: false) })
            menu.addItem(item("Move to Other Pane") { [weak self] in self?.parent.app.transfer(urls, move: true) })
            menu.addItem(.separator())
            let folders = urls.filter { u in items.first { $0.url == u }?.isDirectory ?? false }
            if !folders.isEmpty {
                menu.addItem(.separator())
                menu.addItem(item("Add to Favorites") { [weak self] in
                    self?.parent.app.favorites.insert(Array(folders), before: nil)
                })
            }
            menu.addItem(.separator())
            menu.addItem(item("Move to Trash") { [weak self] in self?.parent.app.trash(urls) })
        }

        @objc private func toggleColumn(_ sender: NSMenuItem) {
            guard let id = sender.representedObject as? String, let table else { return }
            var visible = Self.visibleColumns()
            if visible.contains(id) { visible.remove(id) } else { visible.insert(id) }
            UserDefaults.standard.set(Array(visible), forKey: "fileColumns")
            table.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(id))?.isHidden = !visible.contains(id)
            fillWidth()
        }

        private func item(_ title: String, _ action: @escaping () -> Void) -> NSMenuItem {
            let mi = NSMenuItem(title: title, action: #selector(runAction(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = ActionBox(action)
            return mi
        }

        @objc private func runAction(_ sender: NSMenuItem) {
            (sender.representedObject as? ActionBox)?.run()
        }

        final class ActionBox {
            let run: () -> Void
            init(_ run: @escaping () -> Void) { self.run = run }
        }
    }
}


/// Table that handles the space bar as Quick Look, like Finder.
final class QLTableView: NSTableView {
    weak var qlSource: FileTableView.Coordinator?

    @objc func copy(_ sender: Any?) { qlSource?.copySelection() }
    @objc func paste(_ sender: Any?) { qlSource?.pasteHere() }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36, event.modifierFlags.intersection([.command, .option, .control]).isEmpty {
            qlSource?.renameSelection()
            return
        }
        if event.charactersIgnoringModifiers == " ", event.modifierFlags.intersection([.command, .option, .control]).isEmpty {
            if QLPreviewPanel.sharedPreviewPanelExists(), QLPreviewPanel.shared().isVisible {
                QLPreviewPanel.shared().orderOut(nil)
            } else if selectedRow >= 0 {
                QLPreviewPanel.shared().makeKeyAndOrderFront(nil)
            }
            return
        }
        super.keyDown(with: event)
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = qlSource
        panel.delegate = qlSource
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
    }
}
