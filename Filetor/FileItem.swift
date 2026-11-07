import Foundation

struct FileItem: Identifiable, Hashable {
    let url: URL
    let name: String
    let isDirectory: Bool
    let size: Int64
    let modified: Date
    let kind: String

    var id: URL { url }

    static let keys: [URLResourceKey] = [
        .isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .localizedTypeDescriptionKey
    ]

    init(url: URL) {
        let v = try? url.resourceValues(forKeys: Set(Self.keys))
        self.url = url
        self.name = url.lastPathComponent
        self.isDirectory = v?.isDirectory ?? false
        self.size = Int64(v?.fileSize ?? 0)
        self.modified = v?.contentModificationDate ?? .distantPast
        self.kind = v?.localizedTypeDescription ?? ""
    }
}
