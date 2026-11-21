import SwiftUI
import AppKit
import Quartz
import QuickLookThumbnailing

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
    let iconSize: CGFloat
    let showExtensions: Bool
    let previews: Bool
    let themed: Bool
    let tint: Int
    let loading: Set<URL>
    var showFolder = false

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let c = context.coordinator
        let table = QLTableView()
        table.qlSource = c
        table.style = .plain
        table.allowsMultipleSelection = true
        table.allowsColumnReordering = true
        table.columnAutoresizingStyle = .noColumnAutoresizing
        table.intercellSpacing = NSSize(width: 0, height: 0)
        table.gridStyleMask = []
        table.dataSource = c
        table.delegate = c
        table.target = c
        table.action = #selector(Coordinator.clicked)
        table.doubleAction = #selector(Coordinator.doubleClicked)
        table.registerForDraggedTypes([.fileURL])
        table.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
        table.setDraggingSourceOperationMask(.copy, forLocal: false)

        func add(_ id: String, _ title: String, _ width: CGFloat, min: CGFloat, right: Bool = false) {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            col.title = title
            col.width = Coordinator.savedWidth(id) ?? width
            col.minWidth = min
            col.sortDescriptorPrototype = NSSortDescriptor(key: id, ascending: true)
            col.headerCell.alignment = right ? .right : .left
            table.addTableColumn(col)
        }
        add("name", "Name", 320, min: 140)
        add("folder", "Folder", 200, min: 80)
        add("tags", "Tags", 150, min: 60)
        add("modified", "Date Modified", 150, min: 100)
        add("created", "Date Created", 150, min: 100)
        add("lastOpened", "Date Last Opened", 160, min: 100)
        add("added", "Date Added", 150, min: 100)
        add("kind", "Kind", 130, min: 80)
        add("size", "Size", 90, min: 60, right: true)
        let visible = Coordinator.visibleColumns()
        for col in table.tableColumns { col.isHidden = col.identifier.rawValue != "name" && !visible.contains(col.identifier.rawValue) }
        // Saved column order; Name always stays first.
        let order = (UserDefaults.standard.array(forKey: "columnOrder") as? [String] ?? []).filter { $0 != "name" }
        for (i, id) in order.enumerated() {
            let from = table.column(withIdentifier: NSUserInterfaceItemIdentifier(id))
            if from >= 0, from != i + 1, i + 1 < table.numberOfColumns { table.moveColumn(from, toColumn: i + 1) }
        }
        NotificationCenter.default.addObserver(c, selector: #selector(Coordinator.columnMoved(_:)), name: NSTableView.columnDidMoveNotification, object: table)
        NotificationCenter.default.addObserver(c, selector: #selector(Coordinator.layoutChanged(_:)), name: Coordinator.layoutChangedName, object: nil)
        table.allowsColumnResizing = true
        // User resizing only: an autoresizing Name column would absorb every widening and keep the table locked to the visible width.
        for col in table.tableColumns { col.resizingMask = .userResizingMask }

        NotificationCenter.default.addObserver(c, selector: #selector(Coordinator.columnResized(_:)), name: NSTableView.columnDidResizeNotification, object: table)

        let menu = NSMenu()
        menu.delegate = c
        table.menu = menu
        let oldHeader = table.headerView
        table.headerView = SortHeaderView(frame: oldHeader?.frame ?? NSRect(x: 0, y: 0, width: 0, height: 28))
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

        let settings = [scale, striped ? 1 : 0, compact ? 1 : 0, iconSize, showExtensions ? 1 : 0, previews ? 1 : 0, themed ? 1 : 0, CGFloat(tint)]
        let settingsChanged = settings != c.lastSettings
        let itemsChanged = items != c.items
        c.lastSettings = settings
        let oldItems = c.items
        let oldLoading = c.loading
        c.loading = loading
        c.items = items

        table.usesAlternatingRowBackgroundColors = striped
        // A larger icon makes the row taller. At the default size the rows stay as they were.
        // The row grows with the icon and keeps some air above and below: 8 pt at the default size, 0.4 pt more per extra point.
        let rowPadding = 8 + max(0, iconSize - 17) * 0.4
        table.rowHeight = max((compact ? 20 : 25) * scale, iconSize > 17 ? (iconSize + rowPadding) * scale : 0)

        c.syncing = true
        if let first = sortOrder.first {
            let key = Coordinator.key(for: first)
            let asc = first.order == .forward
            if table.sortDescriptors.first?.key != key || table.sortDescriptors.first?.ascending != asc {
                table.sortDescriptors = [NSSortDescriptor(key: key, ascending: asc)]
            }
        }
        if let fc = table.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("folder")), fc.isHidden == showFolder {
            fc.isHidden = !showFolder
            c.fitName(force: true)
        }
        if itemsChanged || settingsChanged {
            // Reloading while a name is being edited would end the edit, so it waits until the edit is over.
            if c.renaming {
                c.needsReload = true
            } else if !settingsChanged, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                      let change = Coordinator.blockChange(from: oldItems, to: items) {
                // A folder was opened or closed in place: its rows slide in or out instead of the list jumping.
                c.animate(change)
            } else {
                table.reloadData()
            }
        }
        // A folder started or finished reading: only its row changes (arrow or spinner).
        if loading != oldLoading, !itemsChanged, !settingsChanged, !c.renaming {
            let changed = items.indices.filter { oldLoading.contains(items[$0].url) != loading.contains(items[$0].url) }
            if !changed.isEmpty {
                table.reloadData(forRowIndexes: IndexSet(changed), columnIndexes: IndexSet(integersIn: 0..<table.numberOfColumns))
            }
        }
        // Rename happens in the row. Only the pane that holds the item starts it (the active one when both do).
        if let target = app.renameTarget, !c.renaming, items.contains(where: { $0.url == target }),
           pane === app.active || !app.active.items.contains(where: { $0.url == target }) {
            DispatchQueue.main.async { c.beginInlineRename(target) }
        }
        let rows = IndexSet(items.indices.filter { selection.contains(items[$0].url) })
        if table.selectedRowIndexes != rows { table.selectRowIndexes(rows, byExtendingSelection: false) }
        c.syncing = false
        c.styleHeaders()
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate, NSTextFieldDelegate, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
        var parent: FileTableView
        var loading = Set<URL>()
        weak var table: NSTableView?
        var items: [FileItem] = []
        var lastSettings: [CGFloat] = []
        var syncing = false

        private var lastClipWidth: CGFloat = 0

        /// Widths of the columns the user dragged, kept between launches. Name is not saved, it fills the leftover width.
        static func savedWidth(_ id: String) -> CGFloat? {
            guard id != "name", let saved = UserDefaults.standard.dictionary(forKey: "columnWidths") as? [String: Double],
                  let w = saved[id] else { return nil }
            return CGFloat(w)
        }

        // MARK: Column layout shared by all lists (order, visibility, widths)

        static let layoutChangedName = Notification.Name("FiletorColumnLayoutChanged")
        private var applyingLayout = false

        /// Another list changed its columns: follow it, so both panes (and all tabs) look the same.
        @objc func layoutChanged(_ note: Notification) {
            guard let table, (note.object as AnyObject?) !== table else { return }
            applyLayout()
        }

        private func announceLayout() {
            guard !applyingLayout else { return }
            NotificationCenter.default.post(name: Self.layoutChangedName, object: table)
        }

        private func applyLayout() {
            guard let table else { return }
            applyingLayout = true
            defer { applyingLayout = false }
            let visible = Self.visibleColumns()
            for col in table.tableColumns {
                let id = col.identifier.rawValue
                guard id != "name" else { continue }
                // Folder is shown only while searching; the list decides that itself.
                if id != "folder" { col.isHidden = !visible.contains(id) }
                if let w = Self.savedWidth(id) { col.width = w }
            }
            let order = (UserDefaults.standard.array(forKey: "columnOrder") as? [String] ?? []).filter { $0 != "name" }
            for (i, id) in order.enumerated() {
                let from = table.column(withIdentifier: NSUserInterfaceItemIdentifier(id))
                if from >= 0, from != i + 1, i + 1 < table.numberOfColumns { table.moveColumn(from, toColumn: i + 1) }
            }
            fitName(force: true)
        }

        @objc func columnMoved(_ note: Notification) {
            guard let table, !applyingLayout else { return }
            UserDefaults.standard.set(table.tableColumns.map(\.identifier.rawValue), forKey: "columnOrder")
            announceLayout()
        }

        /// Name cannot be moved, and nothing can be dropped in front of it.
        func tableView(_ tableView: NSTableView, shouldReorderColumn columnIndex: Int, toColumn newColumnIndex: Int) -> Bool {
            // AppKit first asks with -1 when the drag starts; only a drop in front of Name (0) is refused.
            columnIndex > 0 && newColumnIndex != 0
        }

        @objc func columnResized(_ note: Notification) {
            guard !applyingLayout, let col = note.userInfo?["NSTableColumn"] as? NSTableColumn, col.identifier.rawValue != "name" else { return }
            var saved = UserDefaults.standard.dictionary(forKey: "columnWidths") as? [String: Double] ?? [:]
            saved[col.identifier.rawValue] = Double(col.width)
            UserDefaults.standard.set(saved, forKey: "columnWidths")
            announceLayout()
        }

        /// Notification entry point: only a change of the visible width re-fits Name. A scroller appearing changes the
        /// clip height only, and re-fitting then would snap a widened Name back.
        @objc func fillWidth() { fitName(force: false) }

        func fitName(force: Bool) {
            guard let table, let clip = table.enclosingScrollView?.contentView,
                  let name = table.tableColumns.first(where: { $0.identifier.rawValue == "name" }) else { return }
            if !force && abs(clip.bounds.width - lastClipWidth) < 0.5 { return }
            lastClipWidth = clip.bounds.width
            let others = table.tableColumns.filter { $0 !== name && !$0.isHidden }.reduce(CGFloat(0)) { $0 + $1.width }
            let spacing = table.intercellSpacing.width * CGFloat(table.numberOfColumns)
            name.width = max(name.minWidth, clip.bounds.width - others - spacing)
        }
        var headerMenu: NSMenu?

        static let optionalColumns: [(id: String, title: String)] = [
            ("modified", "Date Modified"), ("created", "Date Created"), ("lastOpened", "Date Last Opened"),
            ("added", "Date Added"), ("size", "Size"), ("kind", "Kind"), ("tags", "Tags"),
        ]

        static func visibleColumns() -> Set<String> {
            if var saved = UserDefaults.standard.array(forKey: "fileColumns") as? [String] {
                // The Tags column is new: switch it on once for lists saved before it existed.
                if !UserDefaults.standard.bool(forKey: "tagsColumnAdded") {
                    UserDefaults.standard.set(true, forKey: "tagsColumnAdded")
                    saved.append("tags")
                    UserDefaults.standard.set(saved, forKey: "fileColumns")
                }
                return Set(saved)
            }
            return ["modified", "kind", "size", "tags"]
        }

        init(_ parent: FileTableView) { self.parent = parent }

        static func key(for c: KeyPathComparator<FileItem>) -> String {
            if c.keyPath == \FileItem.modified as PartialKeyPath<FileItem> { return "modified" }
            if c.keyPath == \FileItem.created as PartialKeyPath<FileItem> { return "created" }
            if c.keyPath == \FileItem.lastOpened as PartialKeyPath<FileItem> { return "lastOpened" }
            if c.keyPath == \FileItem.added as PartialKeyPath<FileItem> { return "added" }
            if c.keyPath == \FileItem.size as PartialKeyPath<FileItem> { return "size" }
            if c.keyPath == \FileItem.kind as PartialKeyPath<FileItem> { return "kind" }
            if c.keyPath == \FileItem.folder as PartialKeyPath<FileItem> { return "folder" }
            if c.keyPath == \FileItem.tagsText as PartialKeyPath<FileItem> { return "tags" }
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

        /// The selected folder or archive that Space lists instead of showing a Quick Look icon.
        func spacePreviewTarget() -> URL? {
            let urls = previewURLs
            guard urls.count == 1, let url = urls.first else { return nil }
            if ArchiveKind.isArchive(url) { return url }
            let v = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
            return (v?.isDirectory ?? false) && !(v?.isPackage ?? false) ? url : nil
        }

        func renameSelection() {
            let urls = Set(previewURLs)
            if !urls.isEmpty { parent.app.beginRename(urls) }
        }

        // MARK: Rename in the row, like Finder

        var renaming = false
        var needsReload = false
        private var renameOriginal = ""
        private var renameShown = ""
        /// Extension (with the dot) that is not shown while renaming and is added back when the name is confirmed.
        private var renameExtension = ""

        func beginInlineRename(_ url: URL) {
            guard !renaming, let table,
                  let row = items.firstIndex(where: { $0.url == url }),
                  let col = table.tableColumns.firstIndex(where: { $0.identifier.rawValue == "name" }) else { return }
            table.scrollRowToVisible(row)
            guard let cell = table.view(atColumn: col, row: row, makeIfNecessary: true) as? NSTableCellView,
                  let field = cell.textField else { return }
            renaming = true
            renameOriginal = items[row].name
            renameShown = field.stringValue
            let hidesExtension = !parent.showExtensions && !(items[row].isDirectory && !items[row].isPackage)
            let editedName = hidesExtension ? items[row].displayName(showExtension: false) : renameOriginal
            renameExtension = hidesExtension ? String(renameOriginal.dropFirst(editedName.count)) : ""
            field.isEditable = true
            field.isSelectable = true
            field.isBezeled = true
            field.bezelStyle = .squareBezel
            field.drawsBackground = true
            field.backgroundColor = .textBackgroundColor
            field.textColor = .textColor
            (field.cell as? NSTextFieldCell)?.backgroundStyle = .normal
            field.delegate = self
            field.stringValue = editedName
            table.window?.makeFirstResponder(field)
            if hidesExtension {
                field.currentEditor()?.selectedRange = NSRange(location: 0, length: (editedName as NSString).length)
            } else if let editor = field.currentEditor() {
                let name = renameOriginal as NSString
                let ext = name.pathExtension
                let keepAll = items[row].isDirectory || ext.isEmpty || name.length == ext.count + 1
                editor.selectedRange = NSRange(location: 0, length: keepAll ? name.length : name.length - ext.count - 1)
            }
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            guard renaming, let field = obj.object as? NSTextField else { return }
            renaming = false
            let cancelled = (obj.userInfo?["NSTextMovement"] as? Int) == NSTextMovement.cancel.rawValue
            var newName = field.stringValue
            if !renameExtension.isEmpty, !newName.lowercased().hasSuffix(renameExtension.lowercased()) { newName += renameExtension }
            renameExtension = ""
            field.isEditable = false
            field.isSelectable = false
            field.isBezeled = false
            field.drawsBackground = false
            field.stringValue = renameShown
            table?.window?.makeFirstResponder(table)
            if cancelled {
                parent.app.renameTarget = nil
            } else {
                parent.app.renameText = newName
                parent.app.commitRename()
            }
            if needsReload {
                needsReload = false
                DispatchQueue.main.async { [weak self] in self?.table?.reloadData() }
            }
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

        /// While Quick Look is open the arrow keys go to the panel. Pass them on, so they move to the next file.
        func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
            guard event.type == .keyDown, [123, 124, 125, 126].contains(event.keyCode), let table else { return false }
            table.keyDown(with: event)
            return true
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
            let font = NSFont.systemFont(ofSize: (13 + max(0, parent.iconSize - 17) * 0.2) * s)
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
                icon.imageScaling = .scaleProportionallyUpOrDown
                icon.image = NSWorkspace.shared.icon(forFile: item.url.path)
                let iconSide = parent.iconSize * s
                if parent.themed, let style = ThemedFolderIcon.style(for: item) {
                    icon.image = ThemedFolderIcon.image(style.theme, side: iconSide, link: style.link)
                }
                if parent.previews, !item.isDirectory {
                    Self.loadPreview(of: item, side: iconSide, into: icon)
                }
                icon.translatesAutoresizingMaskIntoConstraints = false
                cell.addSubview(icon)
                cell.imageView = icon
                text.stringValue = item.displayName(showExtension: parent.showExtensions)
                // In the plain list, folders open in place: a small arrow in front of the icon, one step in per level.
                var iconLeading: CGFloat = 8
                if parent.pane.treeActive {
                    let x0 = 4 + CGFloat(parent.pane.level(of: item.url)) * 18 * s
                    iconLeading = x0 + 16 * s + 2
                    if item.expandable, parent.pane.loading.contains(item.url) {
                        let spinner = NSProgressIndicator()
                        spinner.style = .spinning
                        spinner.controlSize = .small
                        spinner.isIndeterminate = true
                        spinner.translatesAutoresizingMaskIntoConstraints = false
                        cell.addSubview(spinner)
                        NSLayoutConstraint.activate([
                            spinner.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: x0 + 1),
                            spinner.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                            spinner.widthAnchor.constraint(equalToConstant: 14 * s),
                            spinner.heightAnchor.constraint(equalToConstant: 14 * s),
                        ])
                        spinner.startAnimation(nil)
                    } else if item.expandable {
                        let open = parent.pane.expanded.contains(item.url)
                        let arrow = NSButton()
                        arrow.isBordered = false
                        arrow.imagePosition = .imageOnly
                        arrow.image = NSImage(systemSymbolName: open ? "chevron.down" : "chevron.right", accessibilityDescription: nil)?
                            .withSymbolConfiguration(.init(pointSize: 9 * s, weight: .semibold))
                        arrow.contentTintColor = .secondaryLabelColor
                        arrow.focusRingType = .none
                        arrow.target = self
                        arrow.action = #selector(arrowClicked(_:))
                        arrow.translatesAutoresizingMaskIntoConstraints = false
                        cell.addSubview(arrow)
                        NSLayoutConstraint.activate([
                            arrow.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: x0),
                            arrow.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                            arrow.widthAnchor.constraint(equalToConstant: 16 * s),
                            arrow.heightAnchor.constraint(equalToConstant: 16 * s),
                        ])
                    }
                }
                NSLayoutConstraint.activate([
                    icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: iconLeading),
                    icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    icon.widthAnchor.constraint(equalToConstant: iconSide),
                    icon.heightAnchor.constraint(equalToConstant: iconSide),
                    text.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
                    text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                    text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                ])
            case "tags":
                var colors: [NSColor] = []
                var names: [String] = []
                for t in item.tags {
                    if let c = TagStore.shared.color(for: t) { colors.append(c) } else { names.append(t) }
                }
                text.stringValue = names.joined(separator: " ")
                text.textColor = .secondaryLabelColor
                cell.toolTip = item.tags.isEmpty ? nil : item.tags.joined(separator: ", ")
                var leading = text.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4)
                if !colors.isEmpty {
                    let dots = TagDotsView(colors: colors, scale: s)
                    dots.translatesAutoresizingMaskIntoConstraints = false
                    cell.addSubview(dots)
                    NSLayoutConstraint.activate([
                        dots.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
                        dots.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                        dots.widthAnchor.constraint(equalToConstant: dots.contentWidth),
                        dots.heightAnchor.constraint(equalToConstant: 14 * s),
                    ])
                    leading = text.leadingAnchor.constraint(equalTo: dots.trailingAnchor, constant: names.isEmpty ? 0 : 5)
                }
                NSLayoutConstraint.activate([
                    leading,
                    text.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -8),
                    text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                ])
            case "size":
                if item.isDirectory && !item.sizeCalculated {
                    text.stringValue = UserDefaults.standard.bool(forKey: "calculateFolderSizes") ? "…" : "--"
                } else {
                    text.stringValue = ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file)
                }
                text.textColor = .secondaryLabelColor
                text.alignment = .right
                pin(text, in: cell)
            case "folder":
                text.stringValue = item.folder
                text.textColor = .secondaryLabelColor
                text.lineBreakMode = .byTruncatingHead
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

        /// The column the list is sorted by keeps full contrast, the others are dimmed.
        func styleHeaders() {
            guard let table else { return }
            let active = table.sortDescriptors.first?.key
            for col in table.tableColumns {
                col.headerCell.textColor = col.identifier.rawValue == active ? .labelColor : NSColor.labelColor.withAlphaComponent(0.45)
            }
            table.headerView?.needsDisplay = true
        }

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            styleHeaders()
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
            case "folder": comparator = KeyPathComparator(\FileItem.folder, comparator: .localizedStandard, order: order)
            case "tags": comparator = KeyPathComparator(\FileItem.tagsText, comparator: .localizedStandard, order: order)
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

        private static let previewCache = NSCache<NSString, NSImage>()

        /// Replaces the plain file icon with a preview of the file, read in the background.
        static func loadPreview(of item: FileItem, side: CGFloat, into icon: NSImageView) {
            // Previews are read in steps of 16 points, so dragging the size slider does not start a new read per step.
            let side = (side / 16).rounded(.up) * 16
            let key = "\(item.url.path)|\(Int(side))|\(item.modified.timeIntervalSince1970)" as NSString
            if let hit = previewCache.object(forKey: key) { icon.image = hit; return }
            let request = QLThumbnailGenerator.Request(
                fileAt: item.url,
                size: CGSize(width: side, height: side),
                scale: NSScreen.main?.backingScaleFactor ?? 2,
                representationTypes: .thumbnail
            )
            Task { @MainActor in
                if let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
                    let image = rep.nsImage
                    previewCache.setObject(image, forKey: key)
                    icon.image = image
                }
            }
        }

        enum BlockChange {
            case inserted(Range<Int>)
            case removed(Range<Int>)
        }

        /// Finds out whether the new list is the old one with one block of rows added or taken away.
        /// The block always sits right below its folder, so it never starts at the first row.
        static func blockChange(from old: [FileItem], to new: [FileItem]) -> BlockChange? {
            guard old.count != new.count else { return nil }
            let grew = old.count < new.count
            let small = grew ? old : new
            let big = grew ? new : old
            let n = big.count - small.count
            var i = 0
            while i < small.count, small[i] == big[i] { i += 1 }
            guard i > 0, small[i...] == big[(i + n)...] else { return nil }
            return grew ? .inserted(i..<(i + n)) : .removed(i..<(i + n))
        }

        func animate(_ change: BlockChange) {
            guard let table else { return }
            let folderRow: Int
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.32
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                table.beginUpdates()
                switch change {
                case .inserted(let r):
                    table.insertRows(at: IndexSet(integersIn: r), withAnimation: [.effectFade, .slideDown])
                case .removed(let r):
                    table.removeRows(at: IndexSet(integersIn: r), withAnimation: [.slideUp])
                }
                table.endUpdates()
            }
            switch change {
            case .inserted(let r), .removed(let r): folderRow = r.lowerBound - 1
            }
            // The arrow of the folder itself turns to the other direction.
            table.reloadData(forRowIndexes: IndexSet(integer: folderRow), columnIndexes: IndexSet(integersIn: 0..<table.numberOfColumns))
        }

        @objc func arrowClicked(_ sender: NSButton) {
            guard let table else { return }
            let row = table.row(for: sender)
            guard row >= 0, row < items.count else { return }
            parent.pane.toggleExpanded(items[row].url)
        }

        /// Right arrow: opens the selected folder in place.
        func expandSelected() -> Bool {
            guard parent.pane.treeActive, let table, table.selectedRowIndexes.count == 1,
                  table.selectedRow < items.count else { return false }
            let item = items[table.selectedRow]
            guard item.expandable, !parent.pane.expanded.contains(item.url) else { return false }
            parent.pane.expand(item.url)
            return true
        }

        /// Left arrow: closes the selected folder, or selects the folder that holds the selected item.
        func collapseSelected() -> Bool {
            guard parent.pane.treeActive, let table, table.selectedRowIndexes.count == 1,
                  table.selectedRow < items.count else { return false }
            let item = items[table.selectedRow]
            if item.expandable, parent.pane.expanded.contains(item.url) {
                parent.pane.collapse(item.url)
                return true
            }
            guard parent.pane.level(of: item.url) > 0 else { return false }
            parent.pane.selection = [item.url.deletingLastPathComponent()]
            return true
        }

        @objc func doubleClicked() {
            lastClickRow = -1
            guard let table, table.clickedRow >= 0, table.clickedRow < items.count else { return }
            parent.pane.open([items[table.clickedRow].url])
        }

        // A slow second click on the name of an already selected item starts renaming, as in Finder.
        private var lastClickRow = -1
        private var lastClickTime: TimeInterval = 0

        @objc func clicked() {
            guard let table else { return }
            let row = table.clickedRow, col = table.clickedColumn
            let mods = NSEvent.modifierFlags.intersection([.command, .shift, .option, .control])
            guard row >= 0, row < items.count, col >= 0, mods.isEmpty,
                  table.tableColumns[col].identifier.rawValue == "name",
                  table.selectedRowIndexes.count == 1 else { lastClickRow = -1; return }
            let now = ProcessInfo.processInfo.systemUptime
            let gap = now - lastClickTime
            if row == lastClickRow, gap > NSEvent.doubleClickInterval, gap < 2.0 {
                lastClickRow = -1
                parent.app.beginRename([items[row].url])
            } else {
                lastClickRow = row
                lastClickTime = now
            }
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
                menu.addItem(item("New Project Folder…") { [weak self] in self?.parent.app.projectDialog = true })
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
            menu.addItem(tagsItem(urls))
            menu.addItem(.separator())
            menu.addItem(item("Compress") { [weak self] in self?.parent.app.compress(urls) })
            if urls.contains(where: { FileTools.isArchive($0) }) {
                menu.addItem(item("Decompress") { [weak self] in self?.parent.app.decompress(urls) })
            }
            if urls.count == 1, let only = urls.first, items.first(where: { $0.url == only })?.isDirectory == true {
                menu.addItem(item("Archive Project…") { [weak self] in self?.parent.app.archiveFolder = only })
            }
            if urls.contains(where: { FileTools.isImage($0) }) {
                menu.addItem(.separator())
                menu.addItem(item("Rotate Left") { [weak self] in self?.parent.app.rotateImages(urls, degrees: 270) })
                menu.addItem(item("Rotate Right") { [weak self] in self?.parent.app.rotateImages(urls, degrees: 90) })
                menu.addItem(item("Convert…") { [weak self] in
                    let images = urls.filter { FileTools.isImage($0) }
                    self?.parent.app.convertURLs = images.isEmpty ? nil : images
                })
                let conv = NSMenuItem(title: "Convert Image", action: nil, keyEquivalent: "")
                let sub = NSMenu()
                var formats = [("PNG", "png", "png"), ("JPEG", "jpeg", "jpg"), ("HEIC", "heic", "heic"), ("TIFF", "tiff", "tiff")]
                if FileTools.canWriteWebP { formats.append(("WebP", "webp", "webp")) }
                for (title, fmt, ext) in formats {
                    sub.addItem(item(title) { [weak self] in self?.parent.app.convertImages(urls, format: fmt, ext: ext) })
                }
                conv.submenu = sub
                menu.addItem(conv)
                menu.addItem(item("Optimize…") { [weak self] in self?.parent.app.optimizeImages(urls) })
                menu.addItem(item("Strip Metadata") { [weak self] in self?.parent.app.stripMetadata(urls) })
            }
            menu.addItem(.separator())
            menu.addItem(item("Copy Path") {
                let paths = urls.map(\.path).sorted().joined(separator: "\n")
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(paths, forType: .string)
            })
            menu.addItem(item("Touch") { [weak self] in self?.parent.app.touch(urls) })
            menu.addItem(item("Get Info") { [weak self] in self?.parent.app.getInfo(urls) })
            let shareItems = urls.sorted { $0.path < $1.path }
            let shareMenu = NSMenu()
            for name in [NSSharingService.Name.sendViaAirDrop, .composeEmail, .composeMessage] {
                guard let service = NSSharingService(named: name), service.canPerform(withItems: shareItems) else { continue }
                let mi = item(service.menuItemTitle) { service.perform(withItems: shareItems) }
                let img = service.image.copy() as? NSImage
                img?.size = NSSize(width: 16, height: 16)
                mi.image = img
                shareMenu.addItem(mi)
            }
            if shareMenu.items.isEmpty == false {
                let shareItem = NSMenuItem(title: "Share", action: nil, keyEquivalent: "")
                shareItem.submenu = shareMenu
                menu.addItem(shareItem)
            }
            menu.addItem(item("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting(Array(urls)) })
            menu.addItem(item("Open in Terminal") { [weak self] in
                guard let first = urls.sorted(by: { $0.path < $1.path }).first else { return }
                let isDir = self?.items.first { $0.url == first }?.isDirectory ?? false
                let folder = isDir ? first : first.deletingLastPathComponent()
                NSWorkspace.shared.open([folder],
                                        withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"),
                                        configuration: NSWorkspace.OpenConfiguration())
            })
            menu.addItem(.separator())
            let folders = urls.filter { u in items.first { $0.url == u }?.isDirectory ?? false }
            if !folders.isEmpty {
                menu.addItem(.separator())
                menu.addItem(item("Add to Favorites") { [weak self] in
                    self?.parent.app.favorites.insert(Array(folders), before: nil)
                })
            }
            if parent.pane.searchActive || parent.pane.tagFilter != nil, urls.count == 1, let url = urls.first {
                menu.addItem(.separator())
                menu.addItem(item("Show in Folder") { [weak self] in
                    guard let pane = self?.parent.pane else { return }
                    pane.filter = ""
                    pane.navigate(to: url.deletingLastPathComponent())
                    pane.selection = [url]
                })
            }
            menu.addItem(.separator())
            menu.addItem(item("Move to Trash") { [weak self] in self?.parent.app.trash(urls) })
            menu.addItem(item("Delete Immediately…") { [weak self] in self?.parent.app.deleteImmediately(Set(urls)) })
        }

        var selectedURLs: [URL] {
            guard let table else { return [] }
            return table.selectedRowIndexes.compactMap { items.indices.contains($0) ? items[$0].url : nil }
        }

        @objc private func toggleColumn(_ sender: NSMenuItem) {
            guard let id = sender.representedObject as? String, let table else { return }
            var visible = Self.visibleColumns()
            if visible.contains(id) { visible.remove(id) } else { visible.insert(id) }
            UserDefaults.standard.set(Array(visible), forKey: "fileColumns")
            table.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier(id))?.isHidden = !visible.contains(id)
            fitName(force: true)
            announceLayout()
        }

        private func tagsItem(_ urls: Set<URL>) -> NSMenuItem {
            let store = TagStore.shared
            let chosen = items.filter { urls.contains($0.url) }
            let top = NSMenuItem(title: "Tags", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            for tag in store.all {
                let n = chosen.filter { f in f.tags.contains { store.matches($0, tag.name) } }.count
                let mi = item(tag.name) { [weak self] in self?.parent.app.toggleTag(tag.name, on: urls) }
                mi.state = n == 0 ? .off : (n == chosen.count ? .on : .mixed)
                mi.attributedTitle = FinderTags.menuTitle(tag.name, color: tag.color)
                sub.addItem(mi)
            }
            sub.addItem(.separator())
            sub.addItem(item("New Tag…") { [weak self] in self?.parent.app.newTag(for: urls) })
            if chosen.contains(where: { !$0.tags.isEmpty }) {
                sub.addItem(item("Remove All Tags") { [weak self] in self?.parent.app.removeAllTags(urls) })
            }
            top.submenu = sub
            return top
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

    // Lets the Services submenu of the context menu act on the selected files.
    override func validRequestor(forSendType sendType: NSPasteboard.PasteboardType?, returnType: NSPasteboard.PasteboardType?) -> Any? {
        if returnType == nil, selectedRow >= 0, let t = sendType,
           [NSPasteboard.PasteboardType.fileURL, .URL, .string, NSPasteboard.PasteboardType("NSFilenamesPboardType")].contains(t) {
            return self
        }
        return super.validRequestor(forSendType: sendType, returnType: returnType)
    }

    @objc func writeSelection(to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
        let urls = qlSource?.selectedURLs ?? []
        guard !urls.isEmpty else { return false }
        pboard.clearContents()
        return pboard.writeObjects(urls.map { $0 as NSURL })
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty {
            if event.keyCode == 124, qlSource?.expandSelected() == true { return }
            if event.keyCode == 123, qlSource?.collapseSelected() == true { return }
        }
        if event.keyCode == 36, event.modifierFlags.intersection([.command, .option, .control]).isEmpty {
            qlSource?.renameSelection()
            return
        }
        if event.charactersIgnoringModifiers == " ", event.modifierFlags.intersection([.command, .option, .control]).isEmpty {
            // A second Space closes the folder or archive list.
            if let app = qlSource?.parent.app, app.spacePreview != nil {
                app.spacePreview = nil
                return
            }
            if QLPreviewPanel.sharedPreviewPanelExists(), QLPreviewPanel.shared().isVisible {
                QLPreviewPanel.shared().orderOut(nil)
            } else if let url = qlSource?.spacePreviewTarget() {
                qlSource?.parent.app.spacePreview = url
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


/// Column header where a quick second click sorts again. AppKit counts it as a double-click and skips the sort.
final class SortHeaderView: NSTableHeaderView {
    override func mouseDown(with event: NSEvent) {
        guard event.clickCount > 1, let table = tableView else { super.mouseDown(with: event); return }
        let point = convert(event.locationInWindow, from: nil)
        let index = column(at: point)
        guard index >= 0, index < table.tableColumns.count,
              let proto = table.tableColumns[index].sortDescriptorPrototype else { super.mouseDown(with: event); return }
        // Near a column edge a double-click auto-sizes the column; leave that to AppKit.
        let rect = headerRect(ofColumn: index)
        if point.x < rect.minX + 5 || point.x > rect.maxX - 5 { super.mouseDown(with: event); return }
        let current = table.sortDescriptors.first
        let ascending = current?.key == proto.key ? !(current?.ascending ?? true) : proto.ascending
        table.sortDescriptors = [NSSortDescriptor(key: proto.key, ascending: ascending)]
    }
}
