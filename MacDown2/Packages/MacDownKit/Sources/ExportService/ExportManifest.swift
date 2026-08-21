import Foundation

/// The immutable set of resources an export must carry.
///
/// Built by a transient manifest builder that deduplicates by resource identity
/// and then freezes once; there is exactly one resource truth per export.
public struct ExportManifest: Sendable, Equatable {
    /// Resources in a stable, deterministic order (by identity) so identical
    /// inputs produce byte-identical companion directories.
    public let resources: [ExportResource]

    /// Maps an authored reference (the original URL string from a Markdown
    /// link/image) to the content-addressed companion filename it resolved to.
    ///
    /// This is a record of what happened, not the mechanism: references are
    /// rewritten in the cmark tree during composition, so nothing rewrites the
    /// rendered HTML afterwards. Callers use it to report or audit the mapping.
    public let referenceMap: [String: String]

    public init(resources: [ExportResource], referenceMap: [String: String]) {
        self.resources = resources
        self.referenceMap = referenceMap
    }

    public static let empty = ExportManifest(resources: [], referenceMap: [:])
}
