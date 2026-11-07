import SwiftUI

struct SettingsSheet: View {
    let app: AppModel
    @Environment(\.dismiss) private var dismiss

    @AppStorage("appearance") private var appearance = 0
    @AppStorage("accent") private var accent = 0
    @AppStorage("textSize") private var textSize = 1
    @AppStorage("compactRows") private var compactRows = false
    @AppStorage("striped") private var striped = true
    @AppStorage("foldersFirst") private var foldersFirst = true
    @AppStorage("statusBar") private var statusBar = true
    @AppStorage("startDual") private var startDual = true
    @AppStorage("showSidebar") private var showSidebar = true
    @AppStorage("showHidden") private var showHidden = false
    @AppStorage("deviceName") private var deviceName = ""
    @AppStorage("receiveFolder") private var receiveFolder = NSHomeDirectory() + "/Downloads"

    static let accents: [Color] = [.blue, .purple, .pink, .red, .orange, .green, .gray]
    static let sizeNames = ["S", "M", "L", "XL", "Turbo"]

    private var s: CGFloat { UIScale.value(textSize) }

    private var defaultDeviceName: String { Host.current().localizedName ?? "My Mac" }

    var body: some View {
        @Bindable var tb = app.toolbarModel

        VStack(alignment: .leading, spacing: 20) {
            Text("Customize").font(.system(size: 22 * s))

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 28, verticalSpacing: 16) {
                GridRow {
                    Text("Appearance")
                    Picker("", selection: $appearance) {
                        Text("Light").tag(0)
                        Text("Dark").tag(1)
                        Text("Auto").tag(2)
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 240 * s)
                }
                GridRow {
                    Text("Accent colour")
                    HStack(spacing: 12) {
                        ForEach(Array(Self.accents.enumerated()), id: \.offset) { i, color in
                            Circle()
                                .fill(color)
                                .frame(width: 22 * s, height: 22 * s)
                                .overlay(Circle().strokeBorder(Color.primary.opacity(accent == i ? 0.9 : 0), lineWidth: 2).padding(-4))
                                .onTapGesture { accent = i }
                        }
                    }
                }
                GridRow {
                    Text("Text size")
                    Picker("", selection: $textSize) {
                        ForEach(Array(Self.sizeNames.enumerated()), id: \.offset) { i, n in Text(n).tag(i) }
                    }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 300 * s)
                }
                GridRow(alignment: .firstTextBaseline) {
                    Text("Rows")
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Compact rows", isOn: $compactRows)
                        Toggle("Alternating row colours", isOn: $striped)
                        Toggle("Keep folders on top", isOn: $foldersFirst)
                    }
                }
                GridRow(alignment: .firstTextBaseline) {
                    Text("Window")
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Show item count and free space", isOn: $statusBar)
                        Toggle("Open with two panes", isOn: $startDual)
                        Toggle("Show sidebar", isOn: $showSidebar)
                    }
                }
                GridRow {
                    Text("Toolbar")
                    HStack(spacing: 14) {
                        Button("Customize Toolbar…") {
                            dismiss()
                            DispatchQueue.main.async { app.showCustomize = true }
                        }
                        Toggle("Show labels", isOn: $tb.showLabels)
                            .onChange(of: tb.showLabels) { _, _ in app.toolbarModel.save() }
                    }
                }
                GridRow {
                    Text("Hidden files")
                    Toggle("Show hidden files", isOn: $showHidden)
                }
                GridRow {
                    Text("Name on network")
                    TextField(defaultDeviceName, text: $deviceName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 280 * s)
                }
                GridRow(alignment: .firstTextBaseline) {
                    Text("Save received files in")
                    VStack(alignment: .leading, spacing: 6) {
                        Text(receiveFolder).font(.callout).foregroundStyle(.secondary)
                        Button("Use Current Folder") { receiveFolder = app.active.currentURL.path }
                    }
                }
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .font(.system(size: 13 * s))
        .controlSize(UIScale.controlSize(s))
        .padding(28)
        .frame(width: min(600 * s, 940))
        .onChange(of: showHidden) { _, v in app.setHidden(v) }
    }
}
