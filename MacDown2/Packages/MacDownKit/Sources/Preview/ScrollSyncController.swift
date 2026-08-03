import Foundation

/// Coordinates editor ↔ preview scroll positions using a structural map and
/// measured preview block heights.
///
/// The controller is main-actor isolated because it is updated from SwiftUI
/// geometry preferences and drives scroll views on the main thread.
///
/// Feedback loops (editor scroll → preview scroll → reported as a preview
/// scroll → editor scroll → …) are broken by remembering the block index the
/// *other* side was last asked to move to. When ``previewContentOffsetDidChange(_:)``
/// or ``editorDidScroll(toLine:)`` reports a position that merely confirms the
/// sync we ourselves just requested, that one report is swallowed rather than
/// echoed back.
@MainActor
@Observable
public final class ScrollSyncController {
    public private(set) var map: ScrollSyncMap
    public private(set) var blockHeights: [Int: Double]

    /// The preview scroll fraction the editor wants the preview to adopt.
    /// Consumers should clear this after acting on it.
    public var targetPreviewFraction: Double?

    /// The source line the preview wants the editor to scroll to.
    /// Consumers should clear this after acting on it.
    public var targetSourceLine: Int?

    /// The preview block index we most recently asked the preview to scroll
    /// to because the editor moved. The next ``previewContentOffsetDidChange(_:)``
    /// report that lands on this same block is the preview confirming that
    /// request, not a new user-driven preview scroll, so it is swallowed —
    /// with no time limit, since this is the request we are still waiting on.
    private var lastEditorDrivenBlockIndex: Int?

    /// The preview block index we most recently derived from a
    /// preview-driven scroll and asked the editor to move to. The next
    /// ``editorDidScroll(toLine:)`` report that lands on this same block is
    /// the editor confirming that request, so it is swallowed — with no time
    /// limit, for the same reason as above.
    private var lastPreviewDrivenBlockIndex: Int?

    /// Blocks we asked the preview to scroll to, each paired with when we
    /// asked, kept only for ``echoSuppressionWindow``. See
    /// ``isSuppressedEcho(blockIndex:latchedBlockIndex:recentlyRequested:)``
    /// for why `lastEditorDrivenBlockIndex` alone is not enough during a
    /// continuous scroll gesture.
    private var recentEditorRequestedBlocks: [(index: Int, at: ContinuousClock.Instant)] = []

    /// Blocks we asked the editor to scroll to, each paired with when we
    /// asked. Symmetric counterpart to `recentEditorRequestedBlocks`.
    private var recentPreviewRequestedBlocks: [(index: Int, at: ContinuousClock.Instant)] = []

    /// How long a superseded request's block index is still recognized as
    /// "one we asked for" once a newer request has replaced it as the sticky
    /// latch. See ``isSuppressedEcho(blockIndex:latchedBlockIndex:recentlyRequested:)``.
    private static let echoSuppressionWindow: Duration = .milliseconds(300)

    /// Injected clock, overridable in tests so the suppression window can be
    /// exercised deterministically without real sleeps.
    private let now: () -> ContinuousClock.Instant

    public init(
        map: ScrollSyncMap = ScrollSyncMap(blocks: []),
        blockHeights: [Int: Double] = [:],
        now: @escaping () -> ContinuousClock.Instant = { ContinuousClock.now }
    ) {
        self.map = map
        self.blockHeights = blockHeights
        self.now = now
    }

    /// Call when the editor's visible top line changes. Publishes
    /// `targetPreviewFraction` for the preview to adopt, unless this report
    /// merely confirms a preview-driven scroll already in flight.
    public func editorDidScroll(toLine line: Int) {
        guard let blockIndex = map.blockIndex(forLine: line) else { return }

        // Sticky-plus-recent-history: see `isSuppressedEcho` for why an exact
        // match against the latch alone is not enough.
        if isSuppressedEcho(
            blockIndex: blockIndex,
            latchedBlockIndex: lastPreviewDrivenBlockIndex,
            recentlyRequested: recentPreviewRequestedBlocks
        ) {
            return
        }

        lastPreviewDrivenBlockIndex = nil
        lastEditorDrivenBlockIndex = blockIndex
        recordRequest(blockIndex, into: &recentEditorRequestedBlocks)
        targetPreviewFraction = previewFraction(forLine: line)
    }

    /// Call when the preview's scroll content offset changes, in the same
    /// units as `blockHeights`. Publishes `targetSourceLine` for the editor
    /// to adopt, unless this report merely confirms an editor-driven scroll
    /// already in flight.
    public func previewContentOffsetDidChange(_ offset: Double) {
        // Resolved directly from the raw offset — not by dividing by
        // `totalHeight` and multiplying back in `blockIndex(forPreviewFraction:)`
        // — so an offset that is exactly a block's top edge (as
        // `scrollTo(_:anchor:.top)` produces) cannot be nudged onto the wrong
        // side of that boundary by floating-point round-trip error.
        guard let blockIndex = blockIndex(forContentOffset: offset),
              let line = map.line(forBlockIndex: blockIndex)
        else {
            return
        }

        // Sticky-plus-recent-history: see `isSuppressedEcho` for why an exact
        // match against the latch alone is not enough.
        //
        // Both sides emit their position *repeatedly* for a single user
        // gesture — SwiftUI's `onScrollGeometryChange` fires throughout a
        // scroll, and AppKit posts a bounds-change notification per frame of
        // a smooth scroll. The previous one-shot latch (clear-on-match)
        // therefore absorbed only the first echo and let every subsequent one
        // through, so a single drag in the editor bounced back off the
        // preview as a scroll command and the two panes fought each other.
        // Holding the latch until a genuinely *different* block is reported
        // is what makes one gesture produce one sync.
        if isSuppressedEcho(
            blockIndex: blockIndex,
            latchedBlockIndex: lastEditorDrivenBlockIndex,
            recentlyRequested: recentEditorRequestedBlocks
        ) {
            return
        }

        lastEditorDrivenBlockIndex = nil
        lastPreviewDrivenBlockIndex = blockIndex
        recordRequest(blockIndex, into: &recentPreviewRequestedBlocks)
        targetSourceLine = line
    }

    public func update(map: ScrollSyncMap) {
        guard self.map != map else { return }
        self.map = map

        // A block index recorded against the old map may not identify the
        // same block (or any block) in the new one — e.g. a debounced
        // re-parse can land between an editor-driven scroll being requested
        // and the preview's echo of it. Clearing here means the worst case
        // is one un-suppressed echo (a harmless, self-correcting sync) rather
        // than a stale index silently swallowing or misdirecting a real one.
        lastEditorDrivenBlockIndex = nil
        lastPreviewDrivenBlockIndex = nil
        recentEditorRequestedBlocks.removeAll()
        recentPreviewRequestedBlocks.removeAll()
    }

    public func update(blockHeights: [Int: Double]) {
        guard self.blockHeights != blockHeights else { return }
        self.blockHeights = blockHeights
    }

    /// Returns the preview scroll fraction (0...1) for the given editor line.
    public func previewFraction(forLine line: Int) -> Double? {
        guard let blockIndex = map.blockIndex(forLine: line) else { return nil }
        let total = totalHeight
        guard total > 0 else { return nil }

        let offset = offsetUpTo(blockIndex: blockIndex)
        let blockHeight = height(for: blockIndex)
        let entry = map.entries.first { $0.blockIndex == blockIndex }
        let localProgress = localProgress(in: entry?.lineRange ?? (line ... line), for: line)
        return (offset + blockHeight * localProgress) / total
    }

    /// Returns the editor source line corresponding to a preview scroll fraction.
    public func line(forPreviewFraction fraction: Double) -> Int? {
        let total = totalHeight
        guard total > 0, !map.entries.isEmpty else { return nil }

        let target = fraction * total
        var accumulated: Double = 0
        for entry in map.entries {
            let height = height(for: entry.blockIndex)
            let next = accumulated + height
            if next >= target {
                let local = height > 0 ? (target - accumulated) / height : 0
                let lineCount = entry.lineRange.count
                let offset = Int((Double(lineCount) * local).rounded(.down))
                return min(entry.lineRange.lowerBound + offset, entry.lineRange.upperBound)
            }
            accumulated = next
        }
        return map.entries.last?.lineRange.upperBound
    }

    /// The preview block whose top edge is at or before `fraction` of the
    /// total document height and whose bottom edge is after it — i.e. the
    /// block that is at the top of the viewport when the preview is scrolled
    /// to exactly `fraction`.
    ///
    /// This is the exact inverse of the block-anchored `scrollTo(_:anchor:
    /// .top)` used to drive the preview: scrolling to a block sets the
    /// content offset to precisely that block's accumulated top-of-document
    /// height, so a fraction landing exactly on a block boundary must resolve
    /// to the *later* block (the one whose top it is), not the earlier one.
    /// `line(forPreviewFraction:)` uses the opposite convention (`next >=
    /// target` favors the earlier block) because it targets a specific
    /// *line*, not a block anchor, so it is not reused here.
    public func blockIndex(forPreviewFraction fraction: Double) -> Int? {
        let total = totalHeight
        guard total > 0 else { return nil }
        return blockIndex(forContentOffset: fraction * total)
    }

    // MARK: - Internal helpers

    /// Whether an incoming report of `blockIndex` from one side should be
    /// treated as the echo of a request we ourselves sent to that side,
    /// rather than a fresh user-driven scroll.
    ///
    /// An exact match against `latchedBlockIndex` is the common case — the
    /// gesture settled and the other side's confirming report names the same
    /// block we asked it to move to. But a continuous mouse-wheel scroll
    /// fires `editorDidScroll`/`previewContentOffsetDidChange` many times per
    /// second, and each call overwrites the latch with the *newest* requested
    /// block before an *older* request's async echo (a SwiftUI
    /// `scrollTo`/AppKit bounds-change round trip) has come back. That echo
    /// then names a block that no longer matches the latch, so the old
    /// exact-match-only check let it through as if it were a new,
    /// independent scroll — and applied it to the other side, which visibly
    /// fought the user's still-active wheel gesture ("bounces").
    ///
    /// `recentlyRequested` is what closes that gap: every block we asked for
    /// is remembered for `echoSuppressionWindow`, not just the newest one, so
    /// a stale echo of a superseded-but-still-in-flight request is still
    /// recognized. This must key on the *specific* block index rather than
    /// "any report within the window" — a genuine user-driven scroll to a
    /// block we never asked for can legitimately arrive moments after an
    /// echo of an unrelated request, and must not be swallowed just because
    /// it happened to land inside the same window.
    private func isSuppressedEcho(
        blockIndex: Int,
        latchedBlockIndex: Int?,
        recentlyRequested: [(index: Int, at: ContinuousClock.Instant)]
    ) -> Bool {
        if blockIndex == latchedBlockIndex {
            return true
        }
        let cutoff = now() - Self.echoSuppressionWindow
        return recentlyRequested.contains { $0.index == blockIndex && $0.at > cutoff }
    }

    /// Records that we just asked one side to move to `blockIndex`, pruning
    /// entries older than `echoSuppressionWindow` first so the list stays
    /// bounded during a long scroll gesture.
    private func recordRequest(_ blockIndex: Int, into list: inout [(index: Int, at: ContinuousClock.Instant)]) {
        let cutoff = now() - Self.echoSuppressionWindow
        list.removeAll { $0.at <= cutoff }
        list.append((index: blockIndex, at: now()))
    }

    /// Shared boundary-correct resolver behind ``blockIndex(forPreviewFraction:)``
    /// and ``previewContentOffsetDidChange(_:)``. Takes a raw offset (not a
    /// fraction) so the latter never has to round-trip through division and
    /// remultiplication by `totalHeight`.
    private func blockIndex(forContentOffset offset: Double) -> Int? {
        guard !map.entries.isEmpty else { return nil }

        // Heights are measured asynchronously by the preview, so they are all
        // zero until it has laid out at least once (and again briefly after a
        // re-parse replaces the block list). With every height zero this
        // guard is what stops the loop below from falling through to the
        // final `return` and reporting the LAST block for *any* offset. There
        // is genuinely no mapping available yet; say so instead of guessing.
        guard totalHeight > 0 else { return nil }

        var accumulated: Double = 0
        for entry in map.entries {
            let entryHeight = height(for: entry.blockIndex)

            // A block whose height has not been measured *yet* — as opposed
            // to one that is genuinely near-zero-tall — reports exactly 0
            // (real rendered content, even a bare divider, always occupies
            // some space once the top-of-block padding introduced by
            // `PreviewTypography.gapAbove` is included). Accumulating it as
            // zero-width, as the loop below otherwise would, silently folds
            // its entire true span into whichever LATER block happens to
            // already be measured — misattributing any offset that actually
            // falls inside or after this block to that unrelated one instead.
            //
            // That produced two symptoms that looked unrelated but shared
            // this one cause: scrolling the editor to line 1 (whose block is
            // still unmeasured on a freshly typed document) resolved the
            // preview's confirming echo to some later, already-measured
            // block, which the editor then obeyed — the "scroll to top snaps
            // to the bottom" bug. And scrolling the editor toward the very
            // end, where the newest blocks are least likely to have measured
            // yet, resolved the echo to an earlier block instead of the true
            // last one — "scroll wheel bounces back above the end".
            //
            // We cannot know where the offset truly falls relative to an
            // unmeasured block's real (nonzero, unknown) extent, so this
            // block is the only answer that isn't an outright guess: `offset`
            // is provably at or after `accumulated`, which is this entry's
            // start, and every entry after it is provably beyond our current
            // knowledge once one gap in the measurements is open.
            if entryHeight == 0 {
                return entry.blockIndex
            }

            let next = accumulated + entryHeight
            if offset < next {
                return entry.blockIndex
            }
            accumulated = next
        }
        return map.entries.last?.blockIndex
    }

    private var totalHeight: Double {
        map.entries.reduce(0) { $0 + height(for: $1.blockIndex) }
    }

    private func offsetUpTo(blockIndex: Int) -> Double {
        var offset: Double = 0
        for entry in map.entries {
            if entry.blockIndex == blockIndex {
                return offset
            }
            offset += height(for: entry.blockIndex)
        }
        return offset
    }

    private func height(for blockIndex: Int) -> Double {
        blockHeights[blockIndex, default: 0]
    }

    private func localProgress(in lineRange: ClosedRange<Int>, for line: Int) -> Double {
        let clamped = min(max(line, lineRange.lowerBound), lineRange.upperBound)
        let count = max(lineRange.count - 1, 1)
        return Double(clamped - lineRange.lowerBound) / Double(count)
    }
}
