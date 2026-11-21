import Foundation

struct FileItem: Identifiable, Hashable {
    let url: URL
    let name: String
    let isDirectory: Bool
    /// A bundle such as an app: it is a folder on disk but shown as one file.
    let isPackage: Bool
    /// An alias or a symbolic link.
    let isLink: Bool
    var size: Int64
    /// True once the total size of a folder has been calculated.
    var sizeCalculated = false
    /// Folder of a recursive search result, relative to the searched folder (empty otherwise).
    var folder = ""
    let modified: Date
    let kind: String
    let created: Date
    let added: Date
    let lastOpened: Date
    /// Finder tag names (standard colour tags and named tags).
    var tags: [String]

    var id: URL { url }

    /// The name as shown in lists: without the extension when the extensions are turned off. Folders keep their full name.
    func displayName(showExtension: Bool) -> String {
        if showExtension || (isDirectory && !isPackage) { return name }
        let base = (name as NSString).deletingPathExtension
        return base.isEmpty ? name : base
    }

    /// A folder whose content can be opened in place in the list.
    var expandable: Bool { isDirectory && !isPackage }

    /// Tag names as one text, used for sorting the Tags column.
    var tagsText: String { tags.joined(separator: " ") }

    static let keys: [URLResourceKey] = [
        .isDirectoryKey, .isPackageKey, .isAliasFileKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey, .localizedTypeDescriptionKey,
        .creationDateKey, .addedToDirectoryDateKey, .contentAccessDateKey, .tagNamesKey
    ]

    init(url: URL) {
        let v = try? url.resourceValues(forKeys: Set(Self.keys))
        self.url = url
        self.name = url.lastPathComponent
        self.isDirectory = v?.isDirectory ?? false
        self.isPackage = v?.isPackage ?? false
        self.isLink = (v?.isAliasFile ?? false) || (v?.isSymbolicLink ?? false)
        self.size = Int64(v?.fileSize ?? 0)
        self.modified = v?.contentModificationDate ?? .distantPast
        self.kind = v?.localizedTypeDescription ?? ""
        self.created = v?.creationDate ?? .distantPast
        self.added = v?.addedToDirectoryDate ?? .distantPast
        self.lastOpened = v?.contentAccessDate ?? .distantPast
        self.tags = v?.tagNames ?? []
    }
}
