import Foundation

/// A preview block and the caller's progress (0...1) through it, computed
/// directly from source line positions rather than recovered from a
/// document-wide scroll fraction. See ``ScrollSyncController/targetPreviewBlock``
/// for why the distinction matters.
public struct PreviewBlockTarget: Equatable {
    public let blockIndex: Int
    public let localProgress: Double
}

// MARK: - Outline "reveal heading" jump

public extension ScrollSyncController {
    /// The block containing `line` and the caller's progress (0...1) through
    /// it, computed straight from line positions with no reference to
    /// `totalHeight`. See ``ScrollSyncController/targetPreviewBlock`` for why
    /// publishing this directly — rather than recovering it by
    /// re-dividing/multiplying a `previewFraction(forLine:)` result —
    /// matters.
    func blockTarget(forLine line: Int) -> PreviewBlockTarget? {
        guard let blockIndex = map.blockIndex(forLine: line) else { return nil }
        let entry = map.entries.first { $0.blockIndex == blockIndex }
        let progress = localProgress(in: entry?.lineRange ?? (line ... line), for: line)
        return PreviewBlockTarget(blockIndex: blockIndex, localProgress: progress)
    }

    /// Duration of the outline sidebar's "reveal heading" scroll animation.
    /// `TextualMarkdownPreview` uses this directly for its own (SwiftUI)
    /// animation. `EditorTextSystem.revealSelection`'s AppKit animation
    /// cannot import this module, so it keeps its own matching constant —
    /// see the comment there for why they must stay equal.
    static let jumpAnimationDuration: TimeInterval = 0.2

    /// How long `editorDidScroll(toLine:)` and `previewContentOffsetDidChange(_:)`
    /// ignore every report after `jump(toLine:)`. Must be at least
    /// `jumpAnimationDuration` — the slower side's mid-animation frames are
    /// still arriving until then — plus a small buffer for notification lag,
    /// or a stray frame could still slip through before this window closes.
    internal static let jumpSettleWindow: Duration = .seconds(jumpAnimationDuration) + .milliseconds(60)

    /// Drives the outline sidebar's "reveal heading" jump: publishes an
    /// animated preview scroll target computed directly from `line`, and
    /// opens `isJumping` so the echo/sync machinery ignores every report
    /// for the duration of both sides' jump animations.
    ///
    /// The editor side is driven separately, directly by the caller
    /// (`EditorTextSystem.revealSelection(..., animated: true)`) with the
    /// same source line, rather than deriving its target by reading back
    /// where the other landed — that round trip is what made a jump this
    /// large fragile, since an animated scroll reports many intermediate
    /// positions and, without `isJumping`, each would look like a fresh
    /// scroll to chase instead of the jump's actual target.
    func jump(toLine line: Int) {
        jumpSettleDeadline = now() + Self.jumpSettleWindow
        guard let blockIndex = map.blockIndex(forLine: line) else { return }

        lastPreviewDrivenBlockIndex = nil
        lastEditorDrivenBlockIndex = blockIndex
        recordRequest(blockIndex, into: &recentEditorRequestedBlocks)
        animatesNextPreviewScroll = true
        targetPreviewFraction = previewFraction(forLine: line)
        targetPreviewBlock = blockTarget(forLine: line)
    }

    /// The preview block containing `fraction` of the total document height,
    /// together with `fraction`'s own progress (0...1) through *that specific
    /// block* — what the preview should actually scroll to. Unlike
    /// `blockIndex(forPreviewFraction:)` alone plus a `.top`-anchored
    /// `scrollTo`, which always snaps the block's top edge to the viewport
    /// and so can never reveal the rest of a block taller than the viewport,
    /// pairing this with a proportional `scrollTo` anchor preserves the
    /// position *within* the block that `fraction` actually names.
    func blockIndexAndLocalProgress(forFraction fraction: Double) -> (blockIndex: Int, localProgress: Double)? {
        let total = totalHeight
        guard total > 0 else { return nil }
        let offset = fraction * total
        guard let blockIndex = blockIndex(forContentOffset: offset) else { return nil }
        let blockStart = offsetUpTo(blockIndex: blockIndex)
        let blockHeight = height(for: blockIndex)
        let localProgress = blockHeight > 0 ? (offset - blockStart) / blockHeight : 0
        return (blockIndex, min(max(localProgress, 0), 1))
    }

    /// The block to `scrollTo` for `fraction`, and the vertical anchor
    /// (0...1) to pair it with — what `TextualMarkdownPreview.scroll(to:)`
    /// hands straight to SwiftUI's `scrollTo(_:anchor:)`.
    ///
    /// `preciseBlock`, when the caller has one (``targetPreviewBlock``), is
    /// used in preference to deriving the block from `fraction` — see that
    /// property's doc comment for why the derivation
    /// (`blockIndexAndLocalProgress(forFraction:)`) is a lossy round trip
    /// that can resolve to the block *before* the intended one. `fraction`
    /// is still required as a fallback for callers with no precise block on
    /// hand.
    ///
    /// The anchor is `localProgress` only when the block overflows the
    /// viewport; otherwise it is 0 (`.top`). This is not a cosmetic choice:
    /// `scrollTo(_:anchor:)`'s resulting content offset is `blockTop +
    /// anchorY * (blockHeight - viewportHeight)`. For a block *shorter* than
    /// the viewport — most paragraphs, list items, headings — that second
    /// term is negative for any `anchorY > 0`, so the real offset lands
    /// *above* `blockTop`, spilling into the previous block. The next
    /// `previewContentOffsetDidChange` then reads that spillover back as an
    /// earlier block than the one actually requested, which defeats echo
    /// suppression (`isSuppressedEcho`) and drags the editor backward —
    /// surfaced as the scroll wheel "bouncing back" on ordinary,
    /// non-overflowing scroll-sync ticks. For a block that genuinely
    /// overflows, the same term is non-negative, so the offset never dips
    /// below `blockTop` and the round trip is exact — which is also the
    /// only case a proportional anchor is needed at all: a block that
    /// already fits in the viewport has nothing left to reveal.
    func previewScrollTarget(
        forFraction fraction: Double,
        viewportHeight: Double,
        preciseBlock: PreviewBlockTarget? = nil
    ) -> (blockIndex: Int, anchorY: Double)? {
        let resolved: (blockIndex: Int, localProgress: Double)
        if let preciseBlock {
            resolved = (preciseBlock.blockIndex, preciseBlock.localProgress)
        } else {
            guard let derived = blockIndexAndLocalProgress(forFraction: fraction) else { return nil }
            resolved = derived
        }
        let overflowsViewport = height(for: resolved.blockIndex) > viewportHeight
        return (resolved.blockIndex, overflowsViewport ? resolved.localProgress : 0)
    }
}
