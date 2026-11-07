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
            CommandMenu("Files") {
                Button("New Folder") { app.newFolder() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                Button("Rename…") { app.beginRename(app.active.selection) }
                    .keyboardShortcut(.f2, modifiers: [])
                Divider()
                Button("Copy to Other Pane") { app.transfer(app.active.selection, move: false) }
                    .keyboardShortcut(.f5, modifiers: [])
                Button("Move to Other Pane") { app.transfer(app.active.selection, move: true) }
                    .keyboardShortcut(.f6, modifiers: [])
                Divider()
                Button("Move to Trash") { app.trash(app.active.selection) }
                    .keyboardShortcut(.delete, modifiers: .command)
            }
            CommandGroup(replacing: .saveItem) {
                Button("Close Tab") { app.closeTab() }
                    .keyboardShortcut("w", modifiers: .command)
            }
        }
    }
}
