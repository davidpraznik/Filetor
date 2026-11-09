import SwiftUI

@main struct FiletorApp: App {
    @State private var app = AppModel()

    init() {
        // Filetor has its own tabs; the system tab bar would draw over the toolbar.
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    var body: some Scene {
        WindowGroup {
            ContentView(app: app)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1100, height: 700)
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Tab") { app.newTab() }
                    .keyboardShortcut("t", modifiers: .command)
            }
            CommandGroup(replacing: .appInfo) {
                Button("About Filetor") {
                    let link = "https://github.com/\(UpdateChecker.repo)"
                    let credits = NSMutableAttributedString(
                        string: "github.com/\(UpdateChecker.repo)",
                        attributes: [
                            .link: URL(string: link)!,
                            .font: NSFont.systemFont(ofSize: 11),
                        ]
                    )
                    let center = NSMutableParagraphStyle()
                    center.alignment = .center
                    credits.addAttribute(.paragraphStyle, value: center, range: NSRange(location: 0, length: credits.length))
                    NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
                }
            }
            CommandGroup(replacing: .undoRedo) {
                Button(app.undoTitle ?? "Undo") { app.undo() }
                    .keyboardShortcut("z", modifiers: .command)
                Button(app.redoTitle ?? "Redo") { app.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { app.showSettings = true }
                    .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(after: .toolbar) {
                Button(app.showInfo ? "Hide Info Panel" : "Show Info Panel") { app.showInfo.toggle() }
                    .keyboardShortcut("i", modifiers: [.command, .option])
                Button(app.showShortcuts ? "Hide Keyboard Shortcuts" : "Show Keyboard Shortcuts") { app.showShortcuts.toggle() }
                    .keyboardShortcut("k", modifiers: [.command, .option])
                Button("Actions…") { app.showPalette.toggle() }
                    .keyboardShortcut("k", modifiers: .command)
                Button("Search") { app.focusSearch += 1 }
                    .keyboardShortcut("f", modifiers: .command)
                Button("Customize Toolbar…") { app.showCustomize = true }
                Button("Restore Toolbar Defaults") { app.toolbarModel.restoreDefaults() }
            }
            CommandMenu("Commands") {
                Menu("Open with") {
                    ForEach(app.openApps(for: app.active.selection), id: \.self) { appURL in
                        Button(FileManager.default.displayName(atPath: appURL.path)) {
                            app.open(app.active.selection, with: appURL)
                        }
                    }
                }
                .disabled(app.active.selection.isEmpty)
                Divider()
                Button("New Folder") { app.newFolder() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("Rename…") { app.beginRename(app.active.selection) }
                    .keyboardShortcut(.f2, modifiers: [])
                Divider()
                Button("Duplicate") { app.duplicate(app.active.selection) }
                    .keyboardShortcut("d", modifiers: .command)
                    .disabled(app.active.selection.isEmpty)
                Button("Copy to…") { app.chooseFolderAndTransfer(app.active.selection, move: false) }
                    .disabled(app.active.selection.isEmpty)
                Button("Move to…") { app.chooseFolderAndTransfer(app.active.selection, move: true) }
                    .disabled(app.active.selection.isEmpty)
                Button("Move to Trash") { app.trash(app.active.selection) }
                    .keyboardShortcut(.delete, modifiers: .command)
                    .disabled(app.active.selection.isEmpty)
                Divider()
                Button("Copy to Other Pane") { app.transfer(app.active.selection, move: false) }
                    .keyboardShortcut(.f5, modifiers: [])
                Button("Move to Other Pane") { app.transfer(app.active.selection, move: true) }
                    .keyboardShortcut(.f6, modifiers: [])
                Divider()
                Button("Get Info") { app.getInfo(app.active.selection) }
                    .keyboardShortcut("i", modifiers: .command)
                    .disabled(app.active.selection.isEmpty)
                Button("Compress") { app.compress(app.active.selection) }
                    .disabled(app.active.selection.isEmpty)
                Button("Decompress") { app.decompress(app.active.selection) }
                    .disabled(app.active.selection.isEmpty)
                Divider()
                Button("Rotate Left") { app.rotateImages(app.active.selection, degrees: 270) }
                    .disabled(app.active.selection.isEmpty)
                Button("Rotate Right") { app.rotateImages(app.active.selection, degrees: 90) }
                    .disabled(app.active.selection.isEmpty)
                Menu("Convert Image") {
                    Button("PNG") { app.convertImages(app.active.selection, format: "png", ext: "png") }
                    Button("JPEG") { app.convertImages(app.active.selection, format: "jpeg", ext: "jpg") }
                    Button("HEIC") { app.convertImages(app.active.selection, format: "heic", ext: "heic") }
                    Button("TIFF") { app.convertImages(app.active.selection, format: "tiff", ext: "tiff") }
                }
                .disabled(app.active.selection.isEmpty)
                Divider()
                Button("Find Duplicates…") { app.findDuplicates() }
                Button("Compare Folders…") { app.compareFolders() }
            }
            CommandGroup(replacing: .saveItem) {
                Button("Close Tab") { app.closeTab() }
                    .keyboardShortcut("w", modifiers: .command)
            }
        }
    }
}
