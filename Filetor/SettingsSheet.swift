import SwiftUI
import ServiceManagement

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
    @AppStorage("autoUpdate") private var autoUpdate = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @AppStorage("receiveFolder") private var receiveFolder = NSHomeDirectory() + "/Downloads"

    static let accents: [Color] = [.blue, .purple, .pink, .red, .orange, .green, .gray]
    static let sizeNames = ["S", "M", "L", "XL", "Turbo"]

    private var s: CGFloat { UIScale.value(textSize) }

    /// "Filetor 1.0 (3) · © 2026 David Praznik", read from the app's Info (Xcode target > Info).
    private var aboutLine: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        let copyright = info["NSHumanReadableCopyright"] as? String ?? ""
        return "Filetor \(version) (\(build))" + (copyright.isEmpty ? "" : " · \(copyright)")
    }
    private var defaultDeviceName: String { Host.current().localizedName ?? "My Mac" }

    var body: some View {
        @Bindable var tb = app.toolbarModel
        let w = 340 * s   // width of the control column; Done aligns to its right edge

        VStack(alignment: .leading, spacing: 20) {
            Text("Customize").font(.system(size: 22 * s))

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 28, verticalSpacing: 16) {
                GridRow {
                    Text("Appearance")
                    SegmentedChoice(options: ["Light", "Dark", "Auto"], selection: $appearance, scale: s)
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
                    SegmentedChoice(options: Self.sizeNames, selection: $textSize, scale: s, width: w)
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
                        .buttonStyle(PathsButtonStyle(scale: s))
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
                        .textFieldStyle(PathsTextFieldStyle(scale: s))
                        .frame(width: w)
                }
                GridRow(alignment: .firstTextBaseline) {
                    Text("Save received files in")
                    VStack(alignment: .leading, spacing: 6) {
                        Text(receiveFolder).font(.system(size: 12 * s)).foregroundStyle(.secondary)
                        Button("Use Current Folder") { receiveFolder = app.active.currentURL.path }
                            .buttonStyle(PathsButtonStyle(scale: s))
                    }
                }
                GridRow {
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    Button("Done") { dismiss() }
                        .buttonStyle(PathsButtonStyle(scale: s, prominent: true))
                        .keyboardShortcut(.defaultAction)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }

            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                Toggle("Check for updates automatically", isOn: $autoUpdate)
                HStack(spacing: 12) {
                    Button("Check for updates") { Task { await app.updater.check() } }
                        .buttonStyle(PathsButtonStyle(scale: s))
                    Text(app.updater.message).foregroundStyle(.secondary)
                    if case .available(_, let url) = app.updater.state {
                        Link("Download", destination: url)
                    }
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Text(aboutLine).fontWeight(.semibold)
                HStack {
                    Link("github.com/\(UpdateChecker.repo)", destination: URL(string: "https://github.com/\(UpdateChecker.repo)")!)
                    Spacer(minLength: 14)
                    Link("Release notes", destination: URL(string: "https://github.com/\(UpdateChecker.repo)/releases")!)
                }
            }
        }
        .toggleStyle(PathsCheckboxStyle(scale: s))
        .font(.system(size: 13 * s))
        .padding(28)
        .fixedSize()
        .onChange(of: showHidden) { _, v in app.setHidden(v) }
    }
}
