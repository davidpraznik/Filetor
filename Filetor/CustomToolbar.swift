import SwiftUI
import AppKit

// MARK: - Window drag area (the window has no title bar, the toolbar moves it)

private final class DragNSView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
}

struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragNSView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - Button style

private struct ToolButtonBody: View {
    let configuration: ButtonStyle.Configuration
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.35)
            .contentShape(Rectangle())
    }
}

struct ToolButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ToolButtonBody(configuration: configuration)
    }
}

// MARK: - Toolbar

struct CustomToolbar: View {
    let app: AppModel
    @AppStorage("textSize") private var textSize = 1

    private var model: ToolbarModel { app.toolbarModel }
    private var s: CGFloat { UIScale.value(textSize) }

    private var buttonWidth: CGFloat { (model.showLabels ? 62 : 44) * s }

    private func width(_ kind: String) -> CGFloat {
        switch kind {
        case "backfwd": return 100 * s
        case "title": return 190 * s
        case "search": return 180 * s
        case "space": return 18 * s
        case "flex": return 0
        default: return buttonWidth
        }
    }

    private func split(available: CGFloat) -> (visible: [ToolbarEntry], hidden: [ToolbarEntry]) {
        var used: CGFloat = 0
        var visible: [ToolbarEntry] = []
        var index = 0
        for e in model.entries {
            let w = width(e.kind) + 6
            if used + w > available { break }
            used += w
            visible.append(e)
            index += 1
        }
        return (visible, Array(model.entries[index...]))
    }

    var body: some View {
        GeometryReader { geo in
            let transfersWidth: CGFloat = app.transfers.hasActive ? 70 * s : 0
            let base = geo.size.width - 24 - transfersWidth
            let first = split(available: base)
            let parts = first.hidden.isEmpty ? first : split(available: base - 40 * s)
            let hiddenButtons = parts.hidden.filter { $0.kind != "flex" && $0.kind != "space" && $0.kind != "title" && $0.kind != "search" }

            HStack(alignment: .center, spacing: 6) {
                if model.entries.isEmpty {
                    Spacer(minLength: 0)
                    Button("Customize Toolbar…") { app.showCustomize = true }
                    Button("Restore Defaults") { model.restoreDefaults() }
                }
                ForEach(parts.visible) { entry in
                    entryView(entry)
                }
                if !parts.hidden.isEmpty {
                    if !parts.visible.contains(where: { $0.kind == "flex" }) { Spacer(minLength: 0) }
                    Menu {
                        ForEach(hiddenButtons) { entry in
                            overflowItem(entry)
                        }
                    } label: {
                        Image(systemName: "chevron.right.2")
                            .font(.system(size: 16 * s))
                            .frame(width: 32 * s, height: 30 * s)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .frame(width: 36 * s)
                    .help("More")
                }
                if app.transfers.hasActive {
                    TransferButton(app: app, showLabel: model.showLabels)
                }
            }
            .padding(.horizontal, 12)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
        }
        .frame(height: 64 * s)
        .background(WindowDragArea())
        .background(Color(nsColor: .windowBackgroundColor))
        .contextMenu {
            Button("Customize Toolbar…") { app.showCustomize = true }
            Button(model.showLabels ? "Icon Only" : "Icon and Text") {
                model.showLabels.toggle()
                model.save()
            }
        }
    }

    @ViewBuilder
    private func overflowItem(_ entry: ToolbarEntry) -> some View {
        if entry.kind == "backfwd" {
            Button("Back") { app.active.goBack() }.disabled(!app.active.canGoBack)
            Button("Forward") { app.active.goForward() }.disabled(!app.active.canGoForward)
        } else if let def = ToolCatalog.def(entry.kind) {
            Button(def.title) { def.run(app) }
                .disabled(isDisabled(def))
        }
    }

    private func isDisabled(_ def: ToolDef) -> Bool {
        (def.needsSelection && app.active.selection.isEmpty) || (def.needsDual && !app.dual)
    }

    @ViewBuilder
    private func entryView(_ entry: ToolbarEntry) -> some View {
        switch entry.kind {
        case "flex":
            Spacer(minLength: 0)
        case "space":
            Spacer().frame(width: 18 * s)
        case "backfwd":
            VStack(spacing: 3) {
                HStack(spacing: 0) {
                    Button { app.active.goBack() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15 * s, weight: .medium))
                            .frame(width: 34 * s, height: 28 * s)
                    }
                    .disabled(!app.active.canGoBack)
                    .help("Back")
                    Button { app.active.goForward() } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 15 * s, weight: .medium))
                            .frame(width: 34 * s, height: 28 * s)
                    }
                    .disabled(!app.active.canGoForward)
                    .help("Forward")
                }
                .buttonStyle(.plain)
                .background(Capsule().fill(Color.primary.opacity(0.07)))
                if model.showLabels {
                    Text("Back/Forward").font(.system(size: 12 * s)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 100 * s)
        case "title":
            let name = app.active.currentURL.lastPathComponent
            Text(name.isEmpty ? "/" : name)
                .font(.system(size: 18 * s, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 190 * s, alignment: .leading)
        case "search":
            @Bindable var pane = app.active
            VStack(spacing: 3) {
                FilterField(text: $pane.filter)
                if model.showLabels {
                    Text("Search").font(.system(size: 12 * s)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 180 * s)
        default:
            if let def = ToolCatalog.def(entry.kind) {
                Button { def.run(app) } label: {
                    VStack(spacing: 3) {
                        Image(systemName: def.symbol)
                            .font(.system(size: 19 * s))
                            .frame(width: 42 * s, height: 30 * s)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill((def.isOn?(app) ?? false) ? Color.primary.opacity(0.12) : Color.clear)
                            )
                        if model.showLabels {
                            Text(def.title).font(.system(size: 12 * s)).lineLimit(1)
                        }
                    }
                    .frame(width: buttonWidth - 4)
                }
                .buttonStyle(ToolButtonStyle())
                .disabled(isDisabled(def))
                .help(def.title)
            }
        }
    }
}

struct TransferButton: View {
    let app: AppModel
    let showLabel: Bool
    @AppStorage("textSize") private var textSize = 1
    @State private var show = false

    var body: some View {
        let s = UIScale.value(textSize)
        Button { show.toggle() } label: {
            VStack(spacing: 3) {
                Image(systemName: "arrow.left.arrow.right.circle")
                    .font(.system(size: 19 * s))
                    .frame(width: 42 * s, height: 30 * s)
                if showLabel {
                    Text("\(Int(app.transfers.overall * 100))%").font(.system(size: 12 * s))
                }
            }
            .frame(width: 58 * s)
        }
        .buttonStyle(ToolButtonStyle())
        .help("Transfers")
        .popover(isPresented: $show) { TransferList(manager: app.transfers) }
    }
}

// MARK: - Filter field

struct FilterField: View {
    @Binding var text: String
    @AppStorage("textSize") private var textSize = 1

    var body: some View {
        let s = UIScale.value(textSize)
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Filter", text: $text).textFieldStyle(.plain)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 14 * s))
        .padding(.horizontal, 8)
        .padding(.vertical, 4 * s)
        .frame(width: 174 * s)
        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Customize sheet

struct CustomizeSheet: View {
    let app: AppModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("textSize") private var textSize = 1

    private var model: ToolbarModel { app.toolbarModel }

    var body: some View {
        @Bindable var tb = app.toolbarModel
        let s = UIScale.value(textSize)

        VStack(alignment: .leading, spacing: 16) {
            Text("Customize Toolbar").font(.system(size: 22 * s))
            Text("Click an item to add or remove it, or drag it into the toolbar below. Drag items in the toolbar to reorder them, or out of it to remove them.")
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 108 * s), spacing: 8)], spacing: 12) {
                ForEach(ToolCatalog.palette, id: \.self) { kind in
                    paletteCell(kind, s)
                }
            }
            .dropDestination(for: String.self) { items, _ in
                if let p = items.first { model.removeDropped(p) }
                return true
            }

            Text("Toolbar").foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92 * s), spacing: 8)], alignment: .leading, spacing: 10) {
                ForEach(model.entries) { entry in
                    stripCell(entry, s)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 100 * s, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.15)))
            .dropDestination(for: String.self) { items, _ in
                if let p = items.first { model.drop(p, before: nil) }
                return true
            }

            HStack(spacing: 12) {
                Text("Show")
                SegmentedChoice(
                    options: ["Icon and Text", "Icon Only"],
                    selection: Binding(
                        get: { tb.showLabels ? 0 : 1 },
                        set: { tb.showLabels = ($0 == 0); model.save() }
                    ),
                    scale: s
                )
                Button("Restore Defaults") { model.restoreDefaults() }
                    .buttonStyle(PathsButtonStyle(scale: s))
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(PathsButtonStyle(scale: s, prominent: true))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .font(.system(size: 13 * s))
        .padding(24)
        .frame(width: min(780 * s, 1180))
    }

    private func icon(_ kind: String, size: CGFloat) -> some View {
        Group {
            if kind == "title" {
                Text("Folder").font(.system(size: size - 2)).foregroundStyle(.secondary)
            } else if kind == "search" {
                Image(systemName: "magnifyingglass").font(.system(size: size - 2))
            } else {
                Image(systemName: ToolCatalog.symbol(kind)).font(.system(size: size - 2))
            }
        }
    }

    private func paletteCell(_ kind: String, _ s: CGFloat) -> some View {
        let present = model.contains(kind) && kind != "space" && kind != "flex"
        return VStack(spacing: 6) {
            ZStack {
                Circle().fill(Color.primary.opacity(0.07)).frame(width: 46 * s, height: 46 * s)
                icon(kind, size: 20 * s)
            }
            Text(ToolCatalog.title(kind)).lineLimit(1)
        }
        .opacity(present ? 0.35 : 1)
        .contentShape(Rectangle())
        .onTapGesture { model.toggle(kind) }
        .draggable("new:" + kind)
    }

    private func stripCell(_ entry: ToolbarEntry, _ s: CGFloat) -> some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.07)).frame(width: 40 * s, height: 32 * s)
                icon(entry.kind, size: 16 * s)
            }
            Text(ToolCatalog.title(entry.kind)).font(.system(size: 11.5 * s)).lineLimit(1)
        }
        .frame(width: 92 * s)
        .contentShape(Rectangle())
        .draggable("move:" + entry.id.uuidString)
        .dropDestination(for: String.self) { items, _ in
            if let p = items.first { model.drop(p, before: entry.id) }
            return true
        }
    }
}
