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
        case "view": return 120 * s
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
            let base = geo.size.width - 28 - transfersWidth
            let first = split(available: base)
            let parts = first.hidden.isEmpty ? first : split(available: base - 40 * s)
            let hiddenButtons = parts.hidden.filter { $0.kind != "flex" && $0.kind != "space" && $0.kind != "title" && $0.kind != "search" && $0.kind != "view" }

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
                            .font(.system(size: 16 * s, weight: .light))
                            .foregroundStyle(Color.primary.opacity(0.6))
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
            .padding(.horizontal, 14)
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
                            .font(.system(size: 15 * s, weight: .regular))
                            .foregroundStyle(Color.primary.opacity(0.6))
                            .frame(width: 34 * s, height: 28 * s)
                    }
                    .disabled(!app.active.canGoBack)
                    .help("Back")
                    Button { app.active.goForward() } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 15 * s, weight: .regular))
                            .foregroundStyle(Color.primary.opacity(0.6))
                            .frame(width: 34 * s, height: 28 * s)
                    }
                    .disabled(!app.active.canGoForward)
                    .help("Forward")
                }
                .buttonStyle(.plain)
                .background(Capsule().fill(Color.primary.opacity(0.07)))
                if model.showLabels {
                    Text("Back/Forward").font(.system(size: 10.5 * s)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 100 * s, alignment: .leading)
        case "title":
            Text(CloudLocation.title(for: app.active.currentURL))
                .font(.system(size: 18 * s, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 190 * s, alignment: .leading)
        case "view":
            @Bindable var pane = app.active
            VStack(spacing: 3) {
                HStack(spacing: 2) {
                    ForEach(Array(["list.bullet", "square.grid.2x2", "rectangle.split.3x1"].enumerated()), id: \.offset) { i, name in
                        Image(systemName: name)
                            .font(.system(size: 13 * s))
                            .foregroundStyle(pane.viewMode == i ? AnyShapeStyle(Color.filetor) : AnyShapeStyle(Color.primary.opacity(0.6)))
                            .frame(width: 34 * s, height: 24 * s)
                            .background {
                                if pane.viewMode == i {
                                    RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor))
                                        .shadow(color: .black.opacity(0.12), radius: 0.8, y: 0.5)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { pane.viewMode = i }
                    }
                }
                .padding(2)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.07)))
                .frame(height: 30 * s)
                if model.showLabels {
                    Text("View").font(.system(size: 10.5 * s)).foregroundStyle(Color.primary.opacity(0.6))
                }
            }
            .frame(width: 118 * s)
        case "search":
            @Bindable var pane = app.active
            VStack(spacing: 3) {
                FilterField(text: $pane.filter, subfolders: $pane.searchSubfolders, focusTrigger: app.focusSearch)
                    .onAppear { app.searchFieldVisible = true; app.showFilterBar = false }
                    .onDisappear { app.searchFieldVisible = false }
                if model.showLabels {
                    Text("Search").font(.system(size: 10.5 * s)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 180 * s)
        default:
            if let def = ToolCatalog.def(entry.kind) {
                Button { def.run(app) } label: {
                    VStack(spacing: 3) {
                        Image(systemName: def.symbol)
                            .font(.system(size: 16 * s, weight: .light))
                            .foregroundStyle((def.isOn?(app) ?? false) ? AnyShapeStyle(Color.filetor) : AnyShapeStyle(Color.primary.opacity(0.6)))
                            .frame(width: 42 * s, height: 30 * s)
                        if model.showLabels {
                            Text(def.title).font(.system(size: 10.5 * s)).foregroundStyle(Color.primary.opacity(0.6)).lineLimit(1)
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
                ZStack {
                    Circle().stroke(Color.primary.opacity(0.18), lineWidth: 1.2 * s)
                    Circle()
                        .trim(from: 0, to: max(0.04, min(1, app.transfers.overall)))
                        .stroke(Color.filetor, style: StrokeStyle(lineWidth: 1.6 * s, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.25), value: app.transfers.overall)
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 8.5 * s, weight: .regular))
                        .foregroundStyle(Color.primary.opacity(0.6))
                }
                .frame(width: 21 * s, height: 21 * s)
                .frame(width: 42 * s, height: 30 * s)
                if showLabel {
                    Text("\(Int(app.transfers.overall * 100))%").font(.system(size: 10.5 * s)).foregroundStyle(Color.primary.opacity(0.6))
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
    var subfolders: Binding<Bool>?
    var focusTrigger = 0
    @AppStorage("textSize") private var textSize = 1
    @FocusState private var focused: Bool

    var body: some View {
        let s = UIScale.value(textSize)
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Filter selected pane", text: $text).textFieldStyle(.plain)
                .focused($focused)
                .onChange(of: focusTrigger) { _, _ in focused = true }
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            if let subfolders {
                Button { subfolders.wrappedValue.toggle() } label: {
                    Image(systemName: subfolders.wrappedValue ? "folder.fill" : "folder")
                }
                .buttonStyle(.plain)
                .foregroundStyle(subfolders.wrappedValue ? Color.filetor : Color.secondary)
                .help(subfolders.wrappedValue ? "Searching subfolders" : "Search subfolders")
            }
        }
        .font(.system(size: 12.5 * s))
        .padding(.horizontal, 8)
        .padding(.vertical, 4 * s)
        .frame(width: 174 * s)
        .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Customize sheet

struct CustomizeSheet: View {
    let app: AppModel
    @Environment(\.closePanel) private var dismiss
    @AppStorage("textSize") private var textSize = 1

    private var model: ToolbarModel { app.toolbarModel }

    var body: some View {
        @Bindable var tb = app.toolbarModel
        let s = UIScale.value(textSize)

        VStack(alignment: .leading, spacing: 16) {
            Text("Customize Toolbar").font(.system(size: 22 * s))
            Text("Click an item to add or remove it, or drag it into the toolbar below. Drag items in the toolbar to reorder them, or out of it to remove them.")
                .foregroundStyle(.secondary)

            WrapGrid(cellWidth: 118 * s, rowSpacing: 14 * s) {
                ForEach(ToolCatalog.palette, id: \.self) { kind in
                    paletteCell(kind, s)
                }
            }
            .dropDestination(for: String.self) { items, _ in
                if let p = items.first { model.removeDropped(p) }
                return true
            }

            Text("Toolbar").foregroundStyle(.secondary)
            WrapGrid(cellWidth: 118 * s, rowSpacing: 14 * s) {
                ForEach(model.entries) { entry in
                    stripCell(entry, s)
                }
            }
            .frame(height: stripHeight(s))
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.025)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.15)))
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
                    .background { Button("") { dismiss() }.keyboardShortcut(.cancelAction).opacity(0).frame(width: 0, height: 0) }
            }
        }
        .font(.system(size: 13 * s))
        .padding(24)
        .frame(width: min(780 * s, 1180))
    }

    /// Height of the toolbar strip for the current entry count (computed, so the grey box always fits every row).
    private func stripHeight(_ s: CGFloat) -> CGFloat {
        let inner = min(780 * s, 1180) - 48 - 28
        let cols = max(1, Int(inner / (118 * s)))
        let rows = max(1, (model.entries.count + cols - 1) / cols)
        let cellH = 38 * s + 6 * s + 19 * s
        return CGFloat(rows) * cellH + CGFloat(rows - 1) * 14 * s
    }

    private func bubble(_ kind: String, _ s: CGFloat) -> some View {
        let line = Color.primary.opacity(0.18)
        let h = 38 * s
        return ZStack {
            switch kind {
            case "backfwd":
                Capsule().fill(Color(nsColor: .controlBackgroundColor)).overlay(Capsule().strokeBorder(line))
                    .frame(width: 58 * s, height: h * 0.8)
                HStack(spacing: 8 * s) {
                    Image(systemName: "chevron.left"); Image(systemName: "chevron.right")
                }
                .font(.system(size: 12 * s, weight: .medium))
            case "title":
                Circle().fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(Circle().strokeBorder(line))
                    .frame(width: h, height: h)
                Image(systemName: "folder").font(.system(size: 14 * s))
            case "flex":
                RoundedRectangle(cornerRadius: 7).fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(line))
                    .frame(width: 50 * s, height: h * 0.75)
                Rectangle().fill(Color.primary.opacity(0.45)).frame(width: 30 * s, height: 1)
            case "space":
                RoundedRectangle(cornerRadius: 7).fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(line))
                    .frame(width: 30 * s, height: 30 * s)
            case "search":
                Capsule().fill(Color.primary.opacity(0.07)).frame(width: 60 * s, height: h * 0.7)
                HStack {
                    Image(systemName: "magnifyingglass").font(.system(size: 12 * s))
                        .foregroundStyle(Color.primary.opacity(0.6))
                    Spacer(minLength: 0)
                }
                .padding(.leading, 12 * s)
                .frame(width: 60 * s)
            default:
                Circle().fill(Color(nsColor: .controlBackgroundColor))
                    .overlay(Circle().strokeBorder(line))
                    .frame(width: h, height: h)
                Image(systemName: ToolCatalog.symbol(kind))
                    .font(.system(size: 14 * s, weight: .regular))
            }
        }
        .frame(height: h)
    }

    private func cell(_ kind: String, _ s: CGFloat) -> some View {
        VStack(spacing: 6 * s) {
            bubble(kind, s)
            Text(ToolCatalog.title(kind))
                .font(.system(size: 13 * s))
                .foregroundStyle(Color.primary.opacity(0.6))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    private func paletteCell(_ kind: String, _ s: CGFloat) -> some View {
        let present = model.contains(kind) && kind != "space" && kind != "flex"
        return cell(kind, s)
            .opacity(present ? 0.35 : 1)
            .onTapGesture { model.toggle(kind) }
            .draggable("new:" + kind)
    }

    private func stripCell(_ entry: ToolbarEntry, _ s: CGFloat) -> some View {
        cell(entry.kind, s)
            .draggable("move:" + entry.id.uuidString)
            .dropDestination(for: String.self) { items, _ in
                if let p = items.first { model.drop(p, before: entry.id) }
                return true
            }
    }
}
