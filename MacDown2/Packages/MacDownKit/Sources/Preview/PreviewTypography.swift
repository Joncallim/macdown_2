import SwiftUI
import Textual

/// Tuning knobs for the Markdown preview's typography.
///
/// Textual's ``StructuredText/DefaultStyle`` is otherwise left alone —
/// headings, code blocks, block quotes, lists, and tables all keep their
/// polished defaults. Only the two values that read as cramped at the
/// preview's default (unset) ambient font size are adjusted here.
enum PreviewTypography {
    /// Comfortable body-text size for an article-reading pane. SwiftUI's
    /// `.body` default (~13pt) is tuned for compact UI chrome, not sustained
    /// reading; Textual scales headings, code, and spacing relative to
    /// whatever font is ambient, so this one number sets the whole preview's
    /// scale.
    static let baseFontSize: CGFloat = 15.5

    /// Paragraph line spacing, brought in line with Textual's own other
    /// block styles. The library's default paragraph spacing (`0.23` ×
    /// font size) is noticeably tighter than its block quote (`0.471`) and
    /// code block (`0.39`) defaults — and paragraphs are most of a typical
    /// document, so that mismatch is what reads as "the whole preview is
    /// cramped" rather than a single odd block.
    struct ParagraphStyle: StructuredText.ParagraphStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .textual.lineSpacing(.fontScaled(0.42))
                .textual.blockSpacing(.fontScaled(top: 1.0))
        }
    }

    /// Heading style identical to Textual's `DefaultHeadingStyle` — same
    /// per-level font scale and line spacing — except for the space below a
    /// heading, before the body text that follows it. The default (`0.8`×)
    /// reads as too tight against a paragraph's own top spacing (`1.0`× on
    /// `ParagraphStyle` above); a heading needs to visually separate from
    /// what comes after it more than a paragraph needs to separate from the
    /// next paragraph.
    struct HeadingStyle: StructuredText.HeadingStyle {
        // Textual's own per-level constants aren't exposed for reuse, so
        // these are copied from `DefaultHeadingStyle` — only `bottom` below
        // differs from the library default (`0.8`).
        private static let lineSpacings: [CGFloat] = [0.1, 0.25, 0.143, 0.167, 0.182, 0.471]
        private static let fontScales: [CGFloat] = [2.353, 1.882, 1.647, 1.412, 1.294, 1]

        func makeBody(configuration: Configuration) -> some View {
            let level = min(configuration.headingLevel, 6)
            configuration.label
                .textual.fontScale(Self.fontScales[level - 1])
                .textual.lineSpacing(.fontScaled(Self.lineSpacings[level - 1]))
                .textual.blockSpacing(.fontScaled(top: 1.6, bottom: 1.2))
                .fontWeight(.semibold)
        }
    }
}
