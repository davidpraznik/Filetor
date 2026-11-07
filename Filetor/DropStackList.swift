import SwiftUI
import AppKit

/// The list inside the Drop Stack: click selects, Shift/Command-click selects several,
/// and dragging a selection moves all selected files at once.
struct DropStackList: NSViewRepresentable {
    let urls: [URL]
    let scale: CGFloat
    let onRemove: (Set<URL>) -> Void

    static func rowHeight(_ s: CGFloat) -> CGFloat { 24 * s }

    final class StackTable: NSTableView {
        var onDelete: (() -> Void)?
        override func keyDown(with event: NSEvent) {
            if event.keyCode == 51 || event.keyCode == 117 { onDelete?() } else { super.keyDown(with: event) }
        }
    }

    func makeNSView(context: Context) -> NSScrollView {
        let c = context.coordinator
        let table = StackTable()
        table.headerView = nil
        table.style = .plain
        table.backgroundColor = .clear
        table.allowsMultipleSelection = true
        table.allowsEmptySelection = true
        table.intercellSpacing = .zero
        table.selectionHighlightStyle = .regular
        table.dataSource = c
        table.delegate = c
        table.setDraggingSourceOperationMask([.copy, .move], forLocal: true)
        table.setDraggingSourceOperationMask(.copy, forLocal: false)
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("file"))
        col.resizingMask = .autoresizingMask
        table.addTableColumn(col)
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.onDelete = { [weak c] in c?.removeSelected() }

        let menu = NSMenu()
        menu.addItem(withTitle: "Remove from Drop Stack", action: #selector(Coordinator.removeSelectedAction), keyEquivalent: "").target = c
        table.menu = menu

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        c.table = table
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let c = context.coordinator
        c.parent = self
        guard let table = c.table else { return }
        table.rowHeight = Self.rowHeight(scale)
        if c.urls != urls {
            // Keep the selection of files that are still in the list.
            let keep = Set(table.selectedRowIndexes.compactMap { c.urls.indices.contains($0) ? c.urls[$0] : nil })
            c.urls = urls
            table.reloadData()
            table.selectRowIndexes(IndexSet(urls.indices.filter { keep.contains(urls[$0]) }), byExtendingSelection: false)
        } else {
            table.reloadData()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: DropStackList
        var urls: [URL]
        weak var table: NSTableView?

        init(_ parent: DropStackList) {
            self.parent = parent
            self.urls = parent.urls
        }

        func numberOfRows(in tableView: NSTableView) -> Int { urls.count }

        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
            urls.indices.contains(row) ? urls[row] as NSURL : nil
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard urls.indices.contains(row) else { return nil }
            let s = parent.scale
            let url = urls[row]
            let cell = NSTableCellView()

            let icon = NSImageView(image: NSWorkspace.shared.icon(forFile: url.path))
            icon.translatesAutoresizingMaskIntoConstraints = false

            let text = NSTextField(labelWithString: url.lastPathComponent)
            text.font = .systemFont(ofSize: 13 * s)
            text.lineBreakMode = .byTruncatingTail
            text.translatesAutoresizingMaskIntoConstraints = false

            let remove = NSButton()
            remove.isBordered = false
            remove.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Remove")?
                .withSymbolConfiguration(.init(pointSize: 9 * s, weight: .semibold))
            remove.contentTintColor = NSColor.secondaryLabelColor
            remove.toolTip = "Remove from Drop Stack"
            remove.target = self
            remove.action = #selector(removeOne(_:))
            remove.tag = row
            remove.translatesAutoresizingMaskIntoConstraints = false

            cell.addSubview(icon); cell.addSubview(text); cell.addSubview(remove)
            NSLayoutConstraint.activate([
                icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 16 * s),
                icon.heightAnchor.constraint(equalToConstant: 16 * s),
                text.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6 * s),
                text.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                text.trailingAnchor.constraint(lessThanOrEqualTo: remove.leadingAnchor, constant: -4),
                remove.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                remove.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                remove.widthAnchor.constraint(equalToConstant: 16 * s),
            ])
            return cell
        }

        @objc func removeOne(_ sender: NSButton) {
            guard urls.indices.contains(sender.tag) else { return }
            parent.onRemove([urls[sender.tag]])
        }

        func removeSelected() {
            guard let table else { return }
            let picked = Set(table.selectedRowIndexes.compactMap { urls.indices.contains($0) ? urls[$0] : nil })
            if !picked.isEmpty { parent.onRemove(picked) }
        }

        @objc func removeSelectedAction() { removeSelected() }
    }
}
