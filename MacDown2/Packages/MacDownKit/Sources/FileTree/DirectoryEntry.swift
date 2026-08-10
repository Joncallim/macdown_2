import Foundation

/// A single immediate child of a directory. URL normalization happens here.
public struct DirectoryEntry: Sendable, Equatable, Identifiable, Hashable {
    public let url: URL
    public var id: URL {
        url
    }

    public let name: String
    public let isDirectory: Bool
    public let isHidden: Bool
    public let isPackage: Bool
    public let isSymbolicLink: Bool

    public init(url: URL, isDirectory: Bool, isHidden: Bool, isPackage: Bool, isSymbolicLink: Bool) {
        // `standardizedFileURL` does not add a directory path hint. Rebuild the
        // lexical URL with the known entry kind so `/folder` and `/folder/`
        // cannot become separate tree identities.
        self.url = URL(
            fileURLWithPath: url.standardizedFileURL.path,
            isDirectory: isDirectory
        ).standardizedFileURL
        name = self.url.lastPathComponent
        self.isDirectory = isDirectory
        self.isHidden = isHidden
        self.isPackage = isPackage
        self.isSymbolicLink = isSymbolicLink
    }

    init(
        lexicalParent: URL,
        name: String,
        isDirectory: Bool,
        isHidden: Bool,
        isPackage: Bool,
        isSymbolicLink: Bool
    ) {
        url = lexicalParent.appendingPathComponent(name, isDirectory: isDirectory)
        self.name = name
        self.isDirectory = isDirectory
        self.isHidden = isHidden
        self.isPackage = isPackage
        self.isSymbolicLink = isSymbolicLink
    }
}
