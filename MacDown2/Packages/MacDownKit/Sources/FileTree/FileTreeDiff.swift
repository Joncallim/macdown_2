import Foundation

public struct DirectoryDiff: Sendable, Equatable {
    public let added: [DirectoryEntry]
    public let removed: [DirectoryEntry]
    public let changed: [DirectoryEntry]
    public var isEmpty: Bool {
        added.isEmpty && removed.isEmpty && changed.isEmpty
    }
}

public enum FileTreeDiff {
    public static func diff(old: [DirectoryEntry], new: [DirectoryEntry]) -> DirectoryDiff {
        // Directory URL hints intentionally differ from file URL hints. The
        // physical identity for a rescan is the standardized path, so a
        // directory→file transition is an attribute change, not a removal and
        // re-addition.
        let oldByPath = Dictionary(uniqueKeysWithValues: old.map { ($0.url.path, $0) })
        let newByPath = Dictionary(uniqueKeysWithValues: new.map { ($0.url.path, $0) })
        return DirectoryDiff(
            added: new.filter { oldByPath[$0.url.path] == nil },
            removed: old.filter { newByPath[$0.url.path] == nil },
            changed: new.filter { entry in oldByPath[entry.url.path].map { $0 != entry } ?? false }
        )
    }
}
