import SwiftUI

@main struct FiletorApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView(app: app)
        }
        .defaultSize(width: 1100, height: 700)
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Tab") { app.newTab() }
                    .keyboardShortcut("t", modifiers: .command)
            }
            CommandGroup(replacing: .saveItem) {
                Button("Close Tab") { app.closeTab() }
                    .keyboardShortcut("w", modifiers: .command)
            }
        }
    }
}
