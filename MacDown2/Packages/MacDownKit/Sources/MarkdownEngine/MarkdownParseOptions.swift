import Foundation

/// The parse switches swift-markdown 0.8.0 actually exposes.
///
/// Only `blockDirectives` maps to a real parser flag (`.parseBlockDirectives`).
/// The GFM extensions are not switchable and are not modelled here: tables,
/// task lists and strikethrough are always parsed; GFM extended autolinks are
/// not parsed at all (only CommonMark `<https://…>` autolinks are); footnotes
/// have no engine support (`[^1]` stays literal text). If upstream ever adds
/// per-extension control, add the field then, together with the parser wiring.
///
/// Block directives are OFF by default: with them on, any line starting `@word`
/// (an @-mention, an email-ish fragment) splits its paragraph into a directive
/// block, and an unclosed `@Name {` hides the rest of the document from Preview
/// and export. They are an explicit opt-in (Settings → Markdown).
public struct MarkdownParseOptions: Sendable, Equatable {
    public var blockDirectives: Bool

    public init(blockDirectives: Bool = false) {
        self.blockDirectives = blockDirectives
    }

    public static let `default` = MarkdownParseOptions()
}
