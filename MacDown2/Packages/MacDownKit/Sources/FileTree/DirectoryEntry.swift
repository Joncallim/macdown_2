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
        let normalizedURL = URL(
            fileURLWithPath: url.standardizedFileURL.path,
            isDirectory: isDirectory
        ).standardizedFileURL
        self.init(
            normalizedURL: normalizedURL,
            name: normalizedURL.lastPathComponent,
            isDirectory: isDirectory,
            isHidden: isHidden,
            isPackage: isPackage,
            isSymbolicLink: isSymbolicLink
        )
    }

    init(
        lexicalParent: URL,
        name: String,
        isDirectory: Bool,
        isHidden: Bool,
        isPackage: Bool,
        isSymbolicLink: Bool
    ) {
        self.init(
            url: lexicalParent.appendingPathComponent(name, isDirectory: isDirectory),
            isDirectory: isDirectory,
            isHidden: isHidden,
            isPackage: isPackage,
            isSymbolicLink: isSymbolicLink
        )
    }

    init(
        normalizedLexicalParent: URL,
        name: String,
        isDirectory: Bool,
        isHidden: Bool,
        isPackage: Bool,
        isSymbolicLink: Bool
    ) {
        self.init(
            normalizedURL: normalizedLexicalParent.appendingPathComponent(name, isDirectory: isDirectory),
            name: name,
            isDirectory: isDirectory,
            isHidden: isHidden,
            isPackage: isPackage,
            isSymbolicLink: isSymbolicLink
        )
    }

    private init(
        normalizedURL: URL,
        name: String,
        isDirectory: Bool,
        isHidden: Bool,
        isPackage: Bool,
        isSymbolicLink: Bool
    ) {
        url = normalizedURL
        self.name = name
        self.isDirectory = isDirectory
        self.isHidden = isHidden
        self.isPackage = isPackage
        self.isSymbolicLink = isSymbolicLink
    }
}
