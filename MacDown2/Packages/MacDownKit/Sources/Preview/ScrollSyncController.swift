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
    /// request, not a new user-driven preview scroll, so it is swallowed.
    private var lastEditorDrivenBlockIndex: Int?

    /// The preview block index we most recently derived from a
    /// preview-driven scroll and asked the editor to move to. The next
    /// ``editorDidScroll(toLine:)`` report that lands on this same block is
    /// the editor confirming that request, so it is swallowed.
    private var lastPreviewDrivenBlockIndex: Int?

    public init(map: ScrollSyncMap = ScrollSyncMap(blocks: []), blockHeights: [Int: Double] = [:]) {
        self.map = map
        self.blockHeights = blockHeights
    }

    /// Call when the editor's visible top line changes. Publishes
    /// `targetPreviewFraction` for the preview to adopt, unless this report
    /// merely confirms a preview-driven scroll already in flight.
    public func editorDidScroll(toLine line: Int) {
        guard let blockIndex = map.blockIndex(forLine: line) else { return }

        // Sticky: every report that lands on the latched block is swallowed,
        // not just the first. See `previewContentOffsetDidChange` for why.
        if blockIndex == lastPreviewDrivenBlockIndex {
            return
        }

        lastPreviewDrivenBlockIndex = nil
        lastEditorDrivenBlockIndex = blockIndex
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

        // Sticky: every report that lands on the latched block is swallowed,
        // not just the first.
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
        if blockIndex == lastEditorDrivenBlockIndex {
            return
        }

        lastEditorDrivenBlockIndex = nil
        lastPreviewDrivenBlockIndex = blockIndex
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

    /// Shared boundary-correct resolver behind ``blockIndex(forPreviewFraction:)``
    /// and ``previewContentOffsetDidChange(_:)``. Takes a raw offset (not a
    /// fraction) so the latter never has to round-trip through division and
    /// remultiplication by `totalHeight`.
    private func blockIndex(forContentOffset offset: Double) -> Int? {
        guard !map.entries.isEmpty else { return nil }

        var accumulated: Double = 0
        for entry in map.entries {
            let next = accumulated + height(for: entry.blockIndex)
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
