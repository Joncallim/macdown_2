import Foundation

/// A volume-scoped filesystem identity with a lexical fallback. The identity
/// is used for equivalence only; callers keep their original URL for display.
public struct PhysicalFileIdentity: Hashable, Sendable {
    public let volume: String?
    public let file: String?
    public let lexicalPath: String
    let volumeSupportsCaseSensitiveNames: Bool?

    public init(url: URL) {
        self.init(url: url, volumeSupportsCaseSensitiveNames: nil)
    }

    init(url: URL, volumeSupportsCaseSensitiveNames override: Bool?) {
        let physical = url.resolvingSymlinksInPath().standardizedFileURL
        let values = try? physical.resourceValues(forKeys: [
            .volumeIdentifierKey,
            .fileResourceIdentifierKey,
            .volumeSupportsCaseSensitiveNamesKey,
        ])
        volume = values?.volumeIdentifier.map { String(describing: $0) }
        file = values?.fileResourceIdentifier.map { String(describing: $0) }
        lexicalPath = url.standardizedFileURL.path
        volumeSupportsCaseSensitiveNames = override ?? values?.volumeSupportsCaseSensitiveNames
    }

    public static func matches(_ lhs: URL, _ rhs: URL) -> Bool {
        matches(Self(url: lhs), Self(url: rhs))
    }

    static func matches(_ left: Self, _ right: Self) -> Bool {
        if let volume = left.volume, let file = left.file, volume == right.volume, file == right.file {
            return true
        }
        guard left.volumeSupportsCaseSensitiveNames == false,
              right.volumeSupportsCaseSensitiveNames == false
        else {
            return left.lexicalPath == right.lexicalPath
        }
        return Self.fold(left.lexicalPath) == Self.fold(right.lexicalPath)
    }

    private static func fold(_ path: String) -> String {
        path.precomposedStringWithCanonicalMapping.folding(
            options: [.caseInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }
}
