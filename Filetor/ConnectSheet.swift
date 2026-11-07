import SwiftUI

/// Connect to a network server (smb://, afp://, nfs://, https:// WebDAV). macOS mounts it and it appears under Devices.
struct ConnectSheet: View {
    let app: AppModel
    @Environment(\.closePanel) private var dismiss
    @AppStorage("textSize") private var textSize = 1
    @AppStorage("recentServers") private var recentRaw = ""
    @State private var address = ""

    private var s: CGFloat { UIScale.value(textSize) }
    private var recents: [String] { recentRaw.split(separator: "\n").map(String.init) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Connect to Server").font(.system(size: 22 * s))
            Text("Enter the address of a network share, for example smb://nas.local/media")
                .foregroundStyle(.secondary)
            TextField("smb://server/share", text: $address)
                .textFieldStyle(PathsTextFieldStyle(scale: s))
                .onSubmit(connect)
            if !recents.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recent").foregroundStyle(.secondary)
                    ForEach(recents, id: \.self) { r in
                        Button(r) { address = r }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.filetor)
                    }
                }
            }
            HStack(spacing: 12) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(PathsButtonStyle(scale: s))
                    .keyboardShortcut(.cancelAction)
                Button("Connect", action: connect)
                    .buttonStyle(PathsButtonStyle(scale: s, prominent: true))
                    .keyboardShortcut(.defaultAction)
                    .disabled(URL(string: address.trimmingCharacters(in: .whitespaces))?.scheme == nil)
            }
        }
        .font(.system(size: 13 * s))
        .padding(28)
        .frame(width: 460 * s)
    }

    private func connect() {
        let text = address.trimmingCharacters(in: .whitespaces)
        guard let url = URL(string: text), url.scheme != nil else { return }
        var list = recents.filter { $0 != text }
        list.insert(text, at: 0)
        recentRaw = list.prefix(5).joined(separator: "\n")
        NSWorkspace.shared.open(url)   // macOS asks for the login and mounts the share
        dismiss()
    }
}
