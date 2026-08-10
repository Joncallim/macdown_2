import Foundation

public struct FileTreeFilter: Sendable, Equatable, Codable {
    public var showsHiddenFiles: Bool
    public var supportedFilesOnly: Bool
    public var foldersFirst: Bool

    public init(showsHiddenFiles: Bool = false, supportedFilesOnly: Bool = false, foldersFirst: Bool = true) {
        self.showsHiddenFiles = showsHiddenFiles
        self.supportedFilesOnly = supportedFilesOnly
        self.foldersFirst = foldersFirst
    }
}

public enum FileTreeArrangement {
    public static func arrange(_ entries: [DirectoryEntry], filter: FileTreeFilter,
                               supportedExtensions: Set<String>) -> [DirectoryEntry]
    // swiftlint:disable:next opening_brace
    {
        let filtered = entries.filter { entry in
            guard filter.showsHiddenFiles || !entry.isHidden else { return false }
            return !filter.supportedFilesOnly || entry.isDirectory || supportedExtensions
                .contains(entry.url.pathExtension.lowercased())
        }
        return filtered.sorted { left, right in
            if filter.foldersFirst, left.isDirectory != right.isDirectory {
                return left.isDirectory
            }
            let ordered = left.name.localizedStandardCompare(right.name)
            if ordered == .orderedSame {
                return left.url.path < right.url.path
            }
            return ordered == .orderedAscending
        }
    }
}
