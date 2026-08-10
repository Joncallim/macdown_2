import Foundation

/// A volume-scoped filesystem identity with a lexical fallback. The identity
/// is used for equivalence only; callers keep their original URL for display.
public struct PhysicalFileIdentity: Hashable, Sendable {
    public let volume: String?
    public let file: String?
    public let lexicalFallback: String

    public init(url: URL) {
        let physical = url.resolvingSymlinksInPath().standardizedFileURL
        let values = try? physical.resourceValues(forKeys: [
            .volumeIdentifierKey,
            .fileResourceIdentifierKey,
        ])
        volume = values?.volumeIdentifier.map { String(describing: $0) }
        file = values?.fileResourceIdentifier.map { String(describing: $0) }
        lexicalFallback = Self.fold(url.standardizedFileURL.path)
    }

    public static func matches(_ lhs: URL, _ rhs: URL) -> Bool {
        let left = Self(url: lhs)
        let right = Self(url: rhs)
        if let volume = left.volume, let file = left.file, volume == right.volume, file == right.file {
            return true
        }
        return left.lexicalFallback == right.lexicalFallback
    }

    private static func fold(_ path: String) -> String {
        path.precomposedStringWithCanonicalMapping.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: .current
        )
    }
}
