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
}
