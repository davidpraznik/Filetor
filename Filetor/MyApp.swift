import SwiftUI

@main struct FiletorApp: App {
    @State private var app = AppModel()

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
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { app.showSettings = true }
                    .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(after: .toolbar) {
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
                Button("Share…") { app.share(app.active.selection) }
                    .disabled(app.active.selection.isEmpty)
                Button("Compress") { app.compress(app.active.selection) }
                    .disabled(app.active.selection.isEmpty)
                Button("Decompress") { app.decompress(app.active.selection) }
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
