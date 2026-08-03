import MarkdownEngine
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

    /// Vertical gap to insert *above* a block, given what kind of block it is.
    ///
    /// This exists because Textual's own `blockSpacing` cannot do the job in
    /// this preview. `TextualMarkdownPreview` slices the document into one
    /// `StructuredText` **per block** (so scroll sync can measure each block's
    /// height independently) and stacks them in a `VStack`. Textual's block
    /// spacing separates blocks *within a single* `StructuredText` document,
    /// so between our sliced views it has no effect at all — the real gap was
    /// whatever the `VStack` spacing was, and that was `0`. Hence "extremely
    /// cramped" no matter how the styles below were tuned.
    ///
    /// Applied as top padding on the block itself rather than as `VStack`
    /// spacing, so the gap is inside the frame `onGeometryChange` measures and
    /// the scroll-sync height math stays exact.
    static func gapAbove(_ kind: BlockKind) -> CGFloat {
        switch kind {
        case .heading:
            // A heading opens a new section: it needs clearly more air above
            // it than sits between two paragraphs, or the hierarchy reads flat.
            baseFontSize * 1.6
        case .thematicBreak:
            baseFontSize * 1.4
        default:
            baseFontSize * 0.95
        }
    }

    /// Paragraph line spacing, brought in line with Textual's own other
    /// block styles. The library's default paragraph spacing (`0.23` ×
    /// font size) is noticeably tighter than its block quote (`0.471`) and
    /// code block (`0.39`) defaults — and paragraphs are most of a typical
    /// document, so that mismatch is what reads as "the whole preview is
    /// cramped" rather than a single odd block.
    /// Only sets leading *within* a paragraph. Spacing *between* blocks is
    /// `gapAbove(_:)` — see there for why `blockSpacing` cannot do it here.
    struct ParagraphStyle: StructuredText.ParagraphStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .textual.lineSpacing(.fontScaled(0.5))
        }
    }

    /// Heading style: Textual's `DefaultHeadingStyle` shape, retuned for a
    /// document-reading pane rather than a web-style article page.
    ///
    /// Two changes from the library default, both driven by how they read
    /// against the 15.5pt base above:
    ///
    /// - **Font scales are much smaller.** Textual's defaults top out at
    ///   `2.353` for H1, which multiplied against this base gives a ~36pt
    ///   heading — sized for a wide article column, not a side-by-side
    ///   editor pane, where it just reads as oversized. These top out at
    ///   `1.55` (~24pt H1, ~20pt H2), enough to establish hierarchy without
    ///   dominating the body text they head.
    /// Spacing around a heading is `gapAbove(_:)`, not `blockSpacing` — see
    /// there for why.
    struct HeadingStyle: StructuredText.HeadingStyle {
        private static let lineSpacings: [CGFloat] = [0.15, 0.18, 0.2, 0.22, 0.24, 0.26]
        private static let fontScales: [CGFloat] = [1.55, 1.3, 1.15, 1.05, 1.0, 0.95]

        func makeBody(configuration: Configuration) -> some View {
            let level = min(configuration.headingLevel, 6)
            configuration.label
                .textual.fontScale(Self.fontScales[level - 1])
                .textual.lineSpacing(.fontScaled(Self.lineSpacings[level - 1]))
                .fontWeight(.semibold)
        }
    }
}
