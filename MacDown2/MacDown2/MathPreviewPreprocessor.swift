import Foundation
import Math
import MathRendering
import Preview

/// Rewrites a `PreviewBlock`'s source so a math span that would fail to
/// typeset is visibly flagged before Textual's `.math` syntax extension
/// ever sees it (epic-19-implementation.md §6.1) — Textual's extension
/// itself renders a parse failure as nothing at all, which would silently
/// violate this epic's "malformed math shows a useful local failure state"
/// acceptance criterion. Spans that validate successfully are left
/// byte-for-byte untouched, so Textual's own `.math` extension still does
/// the actual glyph rendering for every valid equation — this preprocessor
/// never renders math itself, it only removes spans Textual would have
/// silently failed on.
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
        let invalidSpans = spans.filter { !isValid($0) }
        guard !invalidSpans.isEmpty else { return source }

        let nsSource = source as NSString
        var result = ""
        var cursor = 0
        for span in invalidSpans {
            guard span.range.lowerBound >= cursor, span.range.upperBound <= nsSource.length else { continue }
            result += nsSource.substring(with: NSRange(location: cursor, length: span.range.lowerBound - cursor))
            result += invalidMathMarker
            cursor = span.range.upperBound
        }
        result += nsSource.substring(from: cursor)
        return result
    }
}
