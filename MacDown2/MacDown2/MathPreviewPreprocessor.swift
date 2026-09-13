import Foundation
import Math
import MathRendering
import Preview

/// Rewrites a `PreviewBlock`'s source for two independent reasons before
/// Textual's `.math` syntax extension ever sees it (epic-19-implementation.md
/// §6.1):
///
/// 1. **Malformed spans are visibly flagged.** Textual's extension renders a
///    parse failure as nothing at all, which would silently violate this
///    epic's "malformed math shows a useful local failure state" acceptance
///    criterion.
/// 2. **A multi-line `$$...$$` block has its internal newlines collapsed to
///    spaces.** Confirmed by reading Textual's own shipped
///    `PatternProcessor.expand` (`Internal/MarkdownParser/PatternProcessor.swift`):
///    it tokenizes each `AttributedString` run's text SEPARATELY, never
///    concatenating across runs, and Foundation's Markdown paragraph parser
///    puts each soft-line-broken line of a paragraph in its own run — so a
///    `$$` opened on one line and closed on a later line can never be seen
///    as one match by Textual's tokenizer, even though the exact same text
///    is one unambiguous match to this epic's own `MathSpanScanner`
///    (confirmed empirically: real Release-app dogfood showed a `$$\nfoo\n$$`
///    block rendering as inert literal text, while the identical equation
///    written as `$$foo$$` on one line rendered correctly). LaTeX math mode
///    does not assign meaning to whitespace/newlines inside an expression,
///    so collapsing them changes nothing about how the equation is
///    interpreted — only whether Textual's per-run tokenizer can see the
///    whole span as one contiguous run. Without this, Preview and Export
///    would disagree on well-formed, everyday multi-line display math,
///    which both `MathSpanScanner` and `MathContribution` already handle
///    correctly (`MathSpanScannerTests.scanMatchesDisplayMathAcrossMultipleLines`,
///    `MathExportRegistryTests`).
///
/// A span needing neither treatment is left byte-for-byte untouched, so
/// Textual's own `.math` extension still does the actual glyph rendering for
/// every valid equation — this preprocessor never renders math itself.
///
/// Applied to `previewContributionSession.displayedBlocks(...)`'s result
/// right before it is handed to `TextualMarkdownPreview(blocks:)`
/// (`DocumentEditorSplitView.swift`) — deliberately outside the
/// `Contributions`/`ContributionRegistry` pipeline (epic-19-implementation.md
/// §4 invariant 5): this is a plain per-block text transform, not a derived
/// contribution result.
enum MathPreviewPreprocessor {
    /// A defensive ceiling on how many spans in one block are validated per
    /// call, analogous to `PreviewContributionBudget.standard`'s 64-result
    /// cap (epic-14-implementation.md §6.6) — far beyond any real block's
    /// equation count, bounding worst-case per-keystroke cost on a
    /// pathological block. Spans beyond this are left untouched (neither
    /// validated nor flagged), never treated as invalid by default.
    static let maxScannedSpansPerBlock = 256

    /// The visible marker a flagged span is replaced with — ordinary inline
    /// code, requiring no new SwiftUI view or hit-testing support this
    /// epic cannot build (epic-19-implementation.md §2.1).
    static let invalidMathMarker = "`⚠ invalid math`"

    static func preprocessed(_ blocks: [PreviewBlock]?) -> [PreviewBlock]? {
        blocks?.map(preprocessed(_:))
    }

    /// Reuses `block.id` unchanged even when `source` is rewritten: `id` is
    /// an opaque SwiftUI identity token here, not recomputed from content at
    /// this layer, so keeping it stable avoids resetting view/scroll-sync
    /// state purely because a span flipped between valid and invalid while
    /// the user is mid-edit.
    static func preprocessed(_ block: PreviewBlock) -> PreviewBlock {
        let rewritten = preprocess(source: block.source)
        guard rewritten != block.source else { return block }
        return PreviewBlock(id: block.id, kind: block.kind, source: rewritten, lineRange: block.lineRange)
    }

    /// `isValid` is injectable so tests can exercise the splicing logic
    /// without depending on `SwiftUIMath`'s real layout — production always
    /// uses `MathImageRenderer.isRenderable`, the exact same check Export's
    /// `MathContribution` renderer relies on for its own failure signal, so
    /// Preview and Export never disagree about which spans are malformed
    /// (epic-19-implementation.md §6.1, §7.1's parity requirement).
    static func preprocess(
        source: String,
        isValid: (MathSpan) -> Bool = MathImageRenderer.isRenderable
    ) -> String {
        let spans = MathSpanScanner.scan(source).prefix(maxScannedSpansPerBlock)
        let nsSource = source as NSString
        var result = ""
        var cursor = 0
        var didRewrite = false

        for span in spans {
            guard span.range.lowerBound >= cursor, span.range.upperBound <= nsSource.length else { continue }
            guard let replacement = replacement(for: span, in: nsSource, isValid: isValid) else { continue }
            result += nsSource.substring(with: NSRange(location: cursor, length: span.range.lowerBound - cursor))
            result += replacement
            cursor = span.range.upperBound
            didRewrite = true
        }

        guard didRewrite else { return source }
        result += nsSource.substring(from: cursor)
        return result
    }

    /// `nil` means "leave this span exactly as authored" — either it is
    /// valid and single-line already, matching what Textual's tokenizer
    /// needs to see it, or something about it prevents a safe rewrite
    /// (neither case applies in practice, but `preprocess` treats `nil` as
    /// "no change" rather than assuming a rewrite always happens).
    private static func replacement(
        for span: MathSpan,
        in nsSource: NSString,
        isValid: (MathSpan) -> Bool
    ) -> String? {
        guard isValid(span) else { return invalidMathMarker }

        let spanText = nsSource.substring(
            with: NSRange(location: span.range.lowerBound, length: span.range.upperBound - span.range.lowerBound)
        )
        guard spanText.contains("\n") else { return nil }
        return spanText.replacingOccurrences(of: "\n", with: " ")
    }
}
