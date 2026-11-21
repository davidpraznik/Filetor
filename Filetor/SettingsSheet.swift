import SwiftUI
import ServiceManagement
import UniformTypeIdentifiers

private enum SettingsPage: String, CaseIterable, Identifiable {
    case general = "General", appearance = "Appearance", rows = "Rows", window = "Window", folderAccess = "Folder Access", ai = "AI", about = "About"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .appearance: "circle.lefthalf.filled"
        case .rows: "list.bullet"
        case .window: "sidebar.left"
        case .folderAccess: "folder"
        case .ai: "sparkles"
        case .about: "info.circle"
        }
    }
}

struct SettingsSheet: View {
    let app: AppModel
    @Environment(\.closePanel) private var dismiss

    @AppStorage("appearance") private var appearance = 0
    @AppStorage("accent") private var accent = 0
    @AppStorage("textSize") private var textSize = 1
    @AppStorage("listIconSize") private var listIconSize = 17.0
    @AppStorage("showExtensions") private var showExtensions = true
    @AppStorage("iconPreviews") private var iconPreviews = false
    @AppStorage("themedFolders") private var themedFolders = false
    @AppStorage("folderColor") private var folderColor = "multi"
    @AppStorage("striped") private var striped = true
    @AppStorage("foldersFirst") private var foldersFirst = true
    @AppStorage("calculateFolderSizes") private var calcFolderSizes = false
    @AppStorage("statusBar") private var statusBar = true
    @AppStorage("startDual") private var startDual = true
    @AppStorage("showSidebar") private var showSidebar = true
    @AppStorage("showHidden") private var showHidden = false
    @AppStorage("autoUpdate") private var autoUpdate = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var page: SettingsPage = .general
    @AppStorage("aiProvider") private var aiProvider = 0
    @AppStorage("aiOtherURL") private var aiOtherURL = ""
    @AppStorage("aiOtherModel") private var aiOtherModel = ""
    @AppStorage("aiLocalAddress") private var aiLocalAddress = AIStore.defaultLocalAddress
    @AppStorage("aiLocalModel") private var aiLocalModel = ""
    @AppStorage("aiSendContents") private var aiSendContents = false
    @State private var apiKeyText = ""
    @State private var otherStatus = ""
    @State private var localStatus = ""
    @State private var localModels: [String] = []
    @State private var testing = false

    static let accents: [Color] = [.blue, .purple, Color(red: 1.0, green: 0.16, blue: 0.67), .red, .orange, .green, .gray]
    static let sizeNames = ["S", "M", "L", "XL", "Turbo"]

    private var s: CGFloat { UIScale.value(textSize) }

    // MARK: Building blocks

    private func group<Content: View>(_ title: String? = nil, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8 * s) {
            if let title {
                Text(title).font(.system(size: 13 * s, weight: .semibold)).padding(.leading, 4)
            }
            VStack(spacing: 0) { content() }
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.1)))
        }
    }

    private func row<Trailing: View>(_ title: String, _ subtitle: String? = nil, last: Bool = false, @ViewBuilder trailing: () -> Trailing) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    if let subtitle {
                        Text(subtitle).font(.system(size: 11 * s)).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 12)
                trailing()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10 * s)
            if !last { Divider().padding(.horizontal, 14) }
        }
    }

    private func switchRow(_ title: String, subtitle: String? = nil, isOn: Binding<Bool>, last: Bool = false) -> some View {
        row(title, subtitle, last: last) {
            Toggle("", isOn: isOn).labelsHidden().toggleStyle(PillSwitchStyle(scale: s))
        }
    }

    private func folderCard(_ title: String, _ subtitle: String, _ image: NSImage, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 44, height: 44)
                Text(title).font(.system(size: 12 * s, weight: .semibold))
                Text(subtitle).font(.system(size: 10 * s)).foregroundStyle(.secondary)
            }
            .frame(width: 140 * s)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.plain)
    }

    /// Slider with Smaller and Bigger under its ends, like the icon size slider in Finder.
    private func iconSlider(value: Binding<Double>, range: ClosedRange<Double>, width: CGFloat) -> some View {
        VStack(spacing: -5 * s) {
            IconSlider(value: value, range: range, scale: s)
            HStack {
                Text("Smaller")
                Spacer(minLength: 0)
                Text("Bigger")
            }
            .font(.system(size: 10 * s))
            .foregroundStyle(.secondary)
        }
        .frame(width: width)
    }

    /// "Filetor 0.1.1 · © 2026 David Praznik", read from the app's Info (Xcode target > Info).
    private var aboutLine: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "?"
        let copyright = info["NSHumanReadableCopyright"] as? String ?? ""
        return "Filetor \(version)" + (copyright.isEmpty ? "" : " · \(copyright)")
    }

    // MARK: Pages

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 7) {
                Button { dismiss() } label: {
                    Circle().fill(Color(red: 0.93, green: 0.42, blue: 0.37)).frame(width: 14, height: 14)
                }
                .buttonStyle(.plain)
                .help("Close")
                Circle().fill(Color.primary.opacity(0.14)).frame(width: 14, height: 14)
                Circle().fill(Color.primary.opacity(0.14)).frame(width: 14, height: 14)
            }
            .padding(.leading, 6)
            .padding(.top, 2)
            .padding(.bottom, 16)
            ForEach(SettingsPage.allCases) { p in
                let on = page == p
                Button { page = p } label: {
                    HStack(spacing: 10) {
                        Image(systemName: p.symbol)
                            .font(.system(size: 13 * s))
                            .foregroundStyle(on ? Color.white : Color.filetor)
                            .frame(width: 20)
                        Text(p.rawValue).foregroundStyle(on ? Color.white : Color.primary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 30 * s)
                    .background(RoundedRectangle(cornerRadius: 8).fill(on ? Color.filetor : Color.clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: 200 * s)
        .frame(maxHeight: .infinity)
        .background(Color.primary.opacity(0.05))
    }

    private func colourDots(_ items: [(id: String, fill: AnyShapeStyle)], selected: String, size: CGFloat, pick: @escaping (String) -> Void) -> some View {
        HStack(spacing: 8) {
            ForEach(items, id: \.id) { item in
                Button { pick(item.id) } label: {
                    Circle().fill(item.fill)
                        .frame(width: size, height: size)
                        .padding(2)
                        .overlay(Circle().stroke(Color.primary.opacity(selected == item.id ? 0.9 : 0), lineWidth: 2))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder private var pageContent: some View {
        @Bindable var tb = app.toolbarModel
        @Bindable var am = app
        switch page {
        case .general:
            group {
                switchRow("Launch at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { on in
                        launchAtLogin = on
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }))
                switchRow("Open with two panes", isOn: $startDual)
                switchRow("Show hidden files", isOn: $showHidden, last: true)
            }
            group("Updates") {
                switchRow("Check for updates automatically", isOn: $autoUpdate)
                if case .available(let version, let url) = app.updater.state {
                    row("Version \(version) is available", "Installed: \(app.updater.installed)") {
                        Button("Download") { NSWorkspace.shared.open(url) }
                            .buttonStyle(PathsButtonStyle(scale: s, prominent: true))
                    }
                }
                row(app.updater.checking ? "Checking…" : app.updater.message, last: true) {
                    HStack(spacing: 8) {
                        if app.updater.checking { ProgressView().controlSize(.small) }
                        Button("Check for updates") { Task { await app.updater.check() } }
                            .buttonStyle(PathsButtonStyle(scale: s))
                            .disabled(app.updater.checking)
                    }
                }
            }
        case .appearance:
            group {
                row("Look") { SegmentedChoice(options: ["Light", "Dark", "Auto"], selection: $appearance, scale: s) }
                row("Accent colour") {
                    colourDots(Self.accents.indices.map { (id: String($0), fill: AnyShapeStyle(Self.accents[$0])) },
                               selected: String(accent), size: 20 * s) { id in
                        if let i = Int(id) { accent = i; AccentStore.shared.index = i }
                    }
                }
                row("Text size", last: true) { SegmentedChoice(options: Self.sizeNames, selection: $textSize, scale: s) }
            }
            group("Folders") {
                row("Style", last: !themedFolders) {
                    HStack(spacing: 10) {
                        folderCard("Finder", "The Mac's own folder", NSWorkspace.shared.icon(for: .folder), selected: !themedFolders) { themedFolders = false }
                        folderCard("Glass", "Filetor's themed folders", ThemedFolderIcon.image(.plain, side: 44, glyph: false), selected: themedFolders) { themedFolders = true }
                    }
                }
                if themedFolders {
                    row("Folder colour", last: true) {
                        colourDots(FolderTint.all.map { t in
                            (id: t.id, fill: t.id == "multi"
                                ? AnyShapeStyle(AngularGradient(colors: [.red, .orange, .yellow, .green, .blue, .purple, .pink, .red], center: .center))
                                : AnyShapeStyle(Color(nsColor: t.light)))
                        }, selected: folderColor, size: 16 * s) { folderColor = $0 }
                    }
                }
            }
        case .rows:
            group {
                row("Row size") { iconSlider(value: $listIconSize, range: 14...40, width: 220 * s) }
                switchRow("Alternating row colours", isOn: $striped)
                switchRow("Keep folders on top", isOn: $foldersFirst)
                switchRow("Calculate all folder sizes", isOn: $calcFolderSizes)
                switchRow("Show file extensions", isOn: $showExtensions)
                switchRow("Show icon previews", isOn: $iconPreviews, last: true)
            }
        case .window:
            group {
                switchRow("Show item count and free space", isOn: $statusBar)
                switchRow("Show sidebar", isOn: $showSidebar)
                switchRow("Show info panel", isOn: $am.showInfo, last: true)
            }
            group("Toolbar") {
                row("Customize toolbar") {
                    Button("Customize Toolbar…") {
                        dismiss()
                        DispatchQueue.main.async { app.showCustomize = true }
                    }
                    .buttonStyle(PathsButtonStyle(scale: s))
                }
                switchRow("Show labels", isOn: $tb.showLabels, last: true)
            }
        case .folderAccess:
            FolderAccessBox(scale: s)
        case .ai:
            group {
                row("Provider", last: true) {
                    // Shown as Off, Local, Other. Stored as 0, 2, 1.
                    SegmentedChoice(options: ["Off", "Local", "Other"],
                                    selection: Binding(
                                        get: { [0: 0, 2: 1, 1: 2][aiProvider] ?? 0 },
                                        set: { aiProvider = [0, 2, 1][$0] }),
                                    scale: s)
                }
            }
            group("Other") {
                row("Address", "OpenAI, Gemini, Mistral, Groq, OpenRouter or any OpenAI-compatible service") {
                    TextField("https://api.openai.com/v1", text: $aiOtherURL)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220 * s)
                }
                row("API key", "Stored in the Keychain on this Mac") {
                    SecureField("Key", text: $apiKeyText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220 * s)
                        .onSubmit { AIStore.setAPIKey(apiKeyText) }
                }
                row("Model") {
                    TextField("Model", text: $aiOtherModel)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220 * s)
                }
                row(otherStatus.isEmpty ? "Check the address, key and model" : otherStatus, last: true) {
                    HStack(spacing: 8) {
                        if testing { ProgressView().controlSize(.small) }
                        Button("Test connection") {
                            AIStore.setAPIKey(apiKeyText)
                            testing = true
                            Task {
                                otherStatus = await AIStore.testOther(base: aiOtherURL, model: aiOtherModel)
                                testing = false
                            }
                        }
                        .buttonStyle(PathsButtonStyle(scale: s))
                        .disabled(testing)
                    }
                }
            }
            .opacity(aiProvider == AIProvider.local.rawValue ? 0.55 : 1)
            group("Local") {
                row("Address") {
                    TextField("Address", text: $aiLocalAddress)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220 * s)
                }
                row("Model") {
                    if localModels.isEmpty {
                        TextField("Model", text: $aiLocalModel)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 220 * s)
                    } else {
                        Picker("", selection: $aiLocalModel) {
                            ForEach(localModels, id: \.self) { Text($0).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                        .frame(width: 220 * s, alignment: .trailing)
                    }
                }
                row(localStatus.isEmpty ? "Look for installed models" : localStatus, last: true) {
                    Button("Find models") {
                        Task {
                            let result = await AIStore.localModels(address: aiLocalAddress)
                            localModels = result.models
                            localStatus = result.message
                            if aiLocalModel.isEmpty || !result.models.contains(aiLocalModel) { aiLocalModel = result.models.first ?? aiLocalModel }
                        }
                    }
                    .buttonStyle(PathsButtonStyle(scale: s))
                }
            }
            .opacity(aiProvider == AIProvider.other.rawValue ? 0.55 : 1)
            group("Privacy") {
                switchRow("Send file contents", subtitle: "Off: only names, dates, sizes and kinds are sent", isOn: $aiSendContents, last: true)
            }
            Text("Nothing is changed without your confirmation. With Local, nothing leaves this Mac.")
                .font(.system(size: 12 * s))
                .foregroundStyle(.secondary)
                .padding(.leading, 4)
        case .about:
            group {
                row(aboutLine, last: false) { EmptyView() }
                row("github.com/\(UpdateChecker.repo)") {
                    Link("Open", destination: URL(string: "https://github.com/\(UpdateChecker.repo)")!)
                }
                row("Release notes", last: true) {
                    Link("Open", destination: URL(string: "https://github.com/\(UpdateChecker.repo)/releases")!)
                }
            }
        }
    }

    var body: some View {
        let maxHeight = (NSScreen.main?.visibleFrame.height ?? 800) - 90
        HStack(spacing: 0) {
            sidebar
            VStack(alignment: .leading, spacing: 16 * s) {
                Text(page.rawValue).font(.system(size: 22 * s, weight: .semibold))
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 22 * s) { pageContent }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 4)
                }
            }
            .padding(26)
            .frame(width: 520 * s)
        }
        .frame(height: min(500 * s, maxHeight))
        .font(.system(size: 13 * s))
        .background { Button("") { dismiss() }.keyboardShortcut(.cancelAction).opacity(0).frame(width: 0, height: 0) }
        .onAppear { apiKeyText = AIStore.apiKey() }
        .onChange(of: showHidden) { _, v in app.setHidden(v) }
        .onChange(of: calcFolderSizes) { _, _ in app.reloadPanes() }
        .onChange(of: app.toolbarModel.showLabels) { _, _ in app.toolbarModel.save() }
    }
}

/// Slider in the Finder look: grey track, accent colour left of the knob, round white knob, no tick marks.
private struct IconSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let scale: CGFloat

    var body: some View {
        GeometryReader { geo in
            let knob = 18 * scale
            let travel = max(geo.size.width - knob, 1)
            let fraction = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
            let x = CGFloat(min(max(fraction, 0), 1)) * travel
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12)).frame(height: 4 * scale)
                Capsule().fill(Color.filetor).frame(width: x + knob / 2, height: 4 * scale)
                Circle()
                    .fill(Color.white)
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                    .frame(width: knob, height: knob)
                    .offset(x: x)
            }
            .frame(height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { g in
                    let f = min(max((g.location.x - knob / 2) / travel, 0), 1)
                    value = (range.lowerBound + Double(f) * (range.upperBound - range.lowerBound)).rounded()
                }
            )
        }
        .frame(height: 22 * scale)
        .accessibilityElement()
        .accessibilityValue("\(Int(value.rounded()))")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(value + 2, range.upperBound)
            case .decrement: value = max(value - 2, range.lowerBound)
            @unknown default: break
            }
        }
    }
}

/// Round switch from the mockup: a pill track and a plain white knob.
private struct PillSwitchStyle: ToggleStyle {
    let scale: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule().fill(configuration.isOn ? Color.filetor : Color.primary.opacity(0.15))
                Circle()
                    .fill(Color.white)
                    .frame(width: 16 * scale, height: 16 * scale)
                    .shadow(color: .black.opacity(0.3), radius: 1, y: 0.5)
                    .padding(2 * scale)
            }
            .frame(width: 36 * scale, height: 20 * scale)
            .animation(.easeInOut(duration: 0.15), value: configuration.isOn)
        }
        .buttonStyle(.plain)
    }
}
