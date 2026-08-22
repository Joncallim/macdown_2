import Foundation

/// Default text encoding for documents that have never been saved before.
///
/// Applies only at the moment a new, untitled document is first written to
/// disk. An already-saved document keeps using its own recorded
/// `FileEncodingMetadata` regardless of this preference — never retroactive
/// (D10, epic-13-implementation.md §4 invariant 2).
public struct FormatSettings: Codable, Sendable, Equatable {
    /// IANA encoding name, e.g. `"utf-8"`.
    public var defaultEncodingForNewDocuments: String

    public init(defaultEncodingForNewDocuments: String = "utf-8") {
        self.defaultEncodingForNewDocuments = defaultEncodingForNewDocuments
    }

    public static let `default` = FormatSettings()
}
