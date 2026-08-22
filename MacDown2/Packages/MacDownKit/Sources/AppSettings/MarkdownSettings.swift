import Foundation

/// Markdown parsing preferences.
///
/// `MarkdownEngine.MarkdownParseOptions` has six fields, but swift-markdown
/// 0.8.0 only honors `blockDirectives` — the other five are always on
/// regardless of their value (see that type's own doc comment). Exposing a
/// toggle a user could set to "off" and see no effect would be a
/// misleading control, not a smaller feature, so this type intentionally
/// carries only the one preference that does something. See
/// epic-13-implementation.md §2.1/§9 for the verification behind this.
public struct MarkdownSettings: Codable, Sendable, Equatable {
    public var parsesBlockDirectives: Bool

    public init(parsesBlockDirectives: Bool = true) {
        self.parsesBlockDirectives = parsesBlockDirectives
    }

    public static let `default` = MarkdownSettings()
}
