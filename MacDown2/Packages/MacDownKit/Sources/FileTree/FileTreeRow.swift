import Foundation

public struct FileTreeRow: Sendable, Equatable, Identifiable {
    public let entry: DirectoryEntry
    public let depth: Int
    public let isExpanded: Bool
    public let isLoading: Bool
    public let loadError: String?
    public var id: URL {
        entry.url
    }

    public init(entry: DirectoryEntry, depth: Int, isExpanded: Bool, isLoading: Bool, loadError: String? = nil) {
        self.entry = entry
        self.depth = depth
        self.isExpanded = isExpanded
        self.isLoading = isLoading
        self.loadError = loadError
    }
}
