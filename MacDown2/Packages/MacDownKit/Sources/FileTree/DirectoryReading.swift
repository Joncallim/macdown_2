import Foundation

public protocol DirectoryReading: Sendable {
    func contents(of url: URL) throws -> [DirectoryEntry]
}

public struct FileSystemDirectoryReader: DirectoryReading {
    public init() {}

    public func contents(of url: URL) throws -> [DirectoryEntry] {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isHiddenKey, .isPackageKey, .isSymbolicLinkKey]
        let lexicalParent = url.standardizedFileURL
        // Enumerate once with prefetched values. A symlinked directory needs
        // its target for the directory stream, but every returned entry is
        // immediately rebound to the lexical parent used by the UI.
        let listingURL = url.resolvingSymlinksInPath()
        return try FileManager.default.contentsOfDirectory(
            at: listingURL,
            includingPropertiesForKeys: Array(keys),
            options: []
        ).map { listedChild in
            let values = try listedChild.resourceValues(forKeys: keys)
            let isSymbolicLink = values.isSymbolicLink == true
            // Most folders contain no links. Keep their hot path entirely in
            // the prefetched resource snapshot; only links need target lookup.
            let targetValues = isSymbolicLink
                ? try? listedChild.resolvingSymlinksInPath().resourceValues(forKeys: keys)
                : nil
            let isDirectory = values.isDirectory == true || targetValues?.isDirectory == true
            return DirectoryEntry(
                normalizedLexicalParent: lexicalParent,
                name: listedChild.lastPathComponent,
                // Resource values describe the link itself on some file
                // systems. Keep the link's lexical URL, but use its target's
                // kind so a symlinked folder remains expandable.
                isDirectory: isDirectory,
                isHidden: values.isHidden == true,
                isPackage: values.isPackage == true || targetValues?.isPackage == true,
                isSymbolicLink: isSymbolicLink
            )
        }
    }
}
