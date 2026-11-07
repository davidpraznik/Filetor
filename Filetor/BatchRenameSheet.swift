import SwiftUI

/// Rename several files at once: replace text, add text, or number them. Shows a live preview.
struct BatchRenameSheet: View {
    let app: AppModel
    let urls: [URL]
    @Environment(\.closePanel) private var dismiss
    @AppStorage("textSize") private var textSize = 1

    @State private var mode = 0
    @State private var find = ""
    @State private var replaceWith = ""
    @State private var addText = ""
    @State private var addAfter = false
    @State private var baseName = ""
    @State private var start = 1

    private var s: CGFloat { UIScale.value(textSize) }

    private func split(_ name: String) -> (stem: String, ext: String) {
        let ns = name as NSString
        let ext = ns.pathExtension
        return ext.isEmpty ? (name, "") : (ns.deletingPathExtension, "." + ext)
    }

    private var newNames: [String] {
        urls.enumerated().map { i, url in
            let (stem, ext) = split(url.lastPathComponent)
            switch mode {
            case 0:
                guard !find.isEmpty else { return url.lastPathComponent }
                return stem.replacingOccurrences(of: find, with: replaceWith) + ext
            case 1:
                return (addAfter ? stem + addText : addText + stem) + ext
            default:
                let base = baseName.isEmpty ? stem : baseName
                return "\(base) \(start + i)" + ext
            }
        }
    }

    private var problem: String? {
        let names = newNames
        if names.contains(where: { $0.trimmingCharacters(in: .whitespaces).isEmpty }) { return "A name cannot be empty." }
        if names.contains(where: { $0.contains("/") }) { return "A name cannot contain \"/\"." }
        if Set(names).count != names.count { return "Two files would get the same name." }
        let own = Set(urls.map { $0.standardizedFileURL.path })
        for (url, name) in zip(urls, names) where name != url.lastPathComponent {
            let dest = url.deletingLastPathComponent().appending(path: name).standardizedFileURL.path
            if FileManager.default.fileExists(atPath: dest) && !own.contains(dest) {
                return "\"\(name)\" already exists in this folder."
            }
        }
        return nil
    }

    private var changed: Bool { zip(urls, newNames).contains { $0.lastPathComponent != $1 } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename \(urls.count) Items").font(.system(size: 22 * s))

            SegmentedChoice(options: ["Replace Text", "Add Text", "Numbering"], selection: $mode, scale: s)

            Group {
                switch mode {
                case 0:
                    field("Find", $find)
                    field("Replace with", $replaceWith)
                case 1:
                    field("Text", $addText)
                    SegmentedChoice(options: ["Before name", "After name"],
                                    selection: Binding(get: { addAfter ? 1 : 0 }, set: { addAfter = ($0 == 1) }), scale: s)
                default:
                    field("Name (empty keeps original)", $baseName)
                    HStack(spacing: 10) {
                        Text("Start at")
                        TextField("1", value: $start, format: .number)
                            .textFieldStyle(PathsTextFieldStyle(scale: s))
                            .frame(width: 80 * s)
                    }
                }
            }

            Text("Preview").foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(zip(urls, newNames).enumerated()), id: \.offset) { _, pair in
                        HStack(spacing: 8) {
                            Text(pair.0.lastPathComponent).foregroundStyle(.secondary).lineLimit(1)
                            Image(systemName: "arrow.right").font(.system(size: 10 * s)).foregroundStyle(.secondary)
                            Text(pair.1).lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
            }
            .frame(height: 170 * s)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.03)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.15)))

            if let problem {
                Text(problem).foregroundStyle(Color.orange)
            }

            HStack(spacing: 12) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(PathsButtonStyle(scale: s))
                    .keyboardShortcut(.cancelAction)
                Button("Rename") {
                    app.applyBatchRename(Array(zip(urls, newNames)))
                    dismiss()
                }
                .buttonStyle(PathsButtonStyle(scale: s, prominent: true))
                .keyboardShortcut(.defaultAction)
                .disabled(problem != nil || !changed)
            }
        }
        .font(.system(size: 13 * s))
        .padding(28)
        .frame(width: 520 * s)
    }

    private func field(_ title: String, _ text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).foregroundStyle(.secondary)
            TextField("", text: text).textFieldStyle(PathsTextFieldStyle(scale: s))
        }
    }
}
