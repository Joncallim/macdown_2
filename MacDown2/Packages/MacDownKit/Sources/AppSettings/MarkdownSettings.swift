import Foundation

/// Markdown parsing preferences.
///
/// `MarkdownEngine.MarkdownParseOptions` exposes only `blockDirectives`,
/// because swift-markdown 0.8.0 has no per-extension switches; this type
/// mirrors that one preference. See epic-13-implementation.md §2.1/§9.
public struct MarkdownSettings: Codable, Sendable, Equatable {
    public var parsesBlockDirectives: Bool

    public init(parsesBlockDirectives: Bool = true) {
        self.parsesBlockDirectives = parsesBlockDirectives
    }

    public static let `default` = MarkdownSettings()
}
