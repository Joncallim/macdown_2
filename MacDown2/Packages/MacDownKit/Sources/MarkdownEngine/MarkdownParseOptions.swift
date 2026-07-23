import Foundation

/// Markdown parsing feature toggles. Defaults match MacDown behaviour (all on).
///
/// swift-markdown 0.8.0 enables the GFM extension set as a whole and does not
/// expose per-extension switches. The struct is kept as the stable shape that
/// E12 (export) and E13 (settings) will consume.
///
/// - `blockDirectives` is the only option currently wired to swift-markdown's
///   `ParseOptions` (via `.parseBlockDirectives`).
/// - The other five options (`tables`, `taskLists`, `strikethrough`,
///   `autolinks`, `footnotes`) record intent for E12/E13 but are always on
///   regardless of their flag values, because swift-markdown enables them
///   together with GFM.
public struct MarkdownParseOptions: Sendable, Equatable {
    public var tables: Bool
    public var taskLists: Bool
    public var strikethrough: Bool
    public var autolinks: Bool
    public var footnotes: Bool
    public var blockDirectives: Bool

    public init(
        tables: Bool = true,
        taskLists: Bool = true,
        strikethrough: Bool = true,
        autolinks: Bool = true,
        footnotes: Bool = true,
        blockDirectives: Bool = true
    ) {
        self.tables = tables
        self.taskLists = taskLists
        self.strikethrough = strikethrough
        self.autolinks = autolinks
        self.footnotes = footnotes
        self.blockDirectives = blockDirectives
    }

    public static let `default` = MarkdownParseOptions()
}
