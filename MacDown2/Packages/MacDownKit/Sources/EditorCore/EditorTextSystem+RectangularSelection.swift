import AppKit

// MARK: - Rectangular (column) selection via Option-drag (EPIC-22 §6.10, Slice 3b-iv)

public extension EditorTextSystem {
    /// Builds one selection range per text LINE (an `NSTextLineFragment` —
    /// a wrapped continuation line counts as its own line here, matching
    /// the gutter/invisibles per-line-fragment iteration convention, not
    /// the source-line-per-`\n` granularity `EditorLineIndex` otherwise
    /// uses) the rectangle between `fromViewPoint` and `toViewPoint`
    /// vertically spans, each column-clamped to that line's own visible
    /// length, and replaces `selectionSet` wholesale with the result.
    ///
    /// Both points are in the text view's own bounds-coordinate space (the
    /// same space `NSEvent.locationInWindow`, converted via
    /// `view.convert(_:from: nil)`, already produces) — callers never need
    /// to pre-subtract `textContainerInset` themselves.
    ///
    /// A rectangular selection deliberately REPLACES `selectionSet`
    /// wholesale rather than merging with whatever selection existed
    /// before the drag began: matching real editors' own convention that
    /// an Option-drag always starts a fresh column selection, not an
    /// addition to unrelated prior carets.
    ///
    /// Returns `false` (no-op, `selectionSet` untouched) when no fragment
    /// can be resolved at the drag's own start point at all — an
    /// essentially unreachable case for a drag that began from a real
    /// mouse-down inside this view, kept only as a defensive guard rather
    /// than force-unwrapping.
    @discardableResult
    func applyRectangularSelection(fromViewPoint: CGPoint, toViewPoint: CGPoint) -> Bool {
        guard let result = rectangularSelection(fromViewPoint: fromViewPoint, toViewPoint: toViewPoint) else {
            return false
        }
        selectionSet = EditorSelectionSet(ranges: result.ranges, primaryIndex: result.primaryIndex)
        return true
    }

    /// The pure geometry `applyRectangularSelection` applies, exposed
    /// separately so tests can assert on the exact produced ranges without
    /// also depending on `EditorSelectionSet`'s own sort/normalize/primary-
    /// relocation behavior in the same assertion.
    func rectangularSelectionRanges(fromViewPoint: CGPoint, toViewPoint: CGPoint) -> [NSRange]? {
        rectangularSelection(fromViewPoint: fromViewPoint, toViewPoint: toViewPoint)?.ranges
    }

    /// Confirmed empirically (a direct probe against this exact TextKit 2
    /// stack, both for a plain multi-paragraph document and for a genuinely
    /// wrapped single paragraph) rather than assumed from documentation
    /// alone: `NSTextLineFragment.characterRange`/`characterIndex(for:)`/
    /// `locationForCharacter(at:)` all operate in an index space LOCAL TO
    /// THE ENCLOSING `NSTextLayoutFragment` (accumulating across wrapped
    /// continuation lines within one fragment — a second wrapped line's
    /// own `characterRange` starts where the first one's ends, not at 0
    /// again), while each line's own POINT geometry (`x`) resets to 0 at
    /// that line's own left edge. `characterIndex(for:)` was also found to
    /// clamp gracefully at a line's own boundaries for an out-of-range x —
    /// stopping one character short of a trailing paragraph terminator on
    /// a paragraph's own final wrapped line, or exactly at the wrap
    /// boundary for a non-final wrapped line — which is already exactly
    /// the "column-clamped to that line's own length" behavior this
    /// feature needs, with no additional manual clamping required.
    private func rectangularSelection(
        fromViewPoint: CGPoint,
        toViewPoint: CGPoint
    ) -> (ranges: [NSRange], primaryIndex: Int)? {
        let inset = textView.textContainerInset
        let minX = min(fromViewPoint.x, toViewPoint.x) - inset.width
        let maxX = max(fromViewPoint.x, toViewPoint.x) - inset.width
        let minY = min(fromViewPoint.y, toViewPoint.y) - inset.height
        let maxY = max(fromViewPoint.y, toViewPoint.y) - inset.height
        // The live end's own container-space Y — used below to pick which
        // produced range becomes the new primary, so the primary follows
        // wherever the mouse currently is, matching native AppKit
        // drag-selection's own convention, rather than always being the
        // top-most or bottom-most range regardless of drag direction.
        let targetY = toViewPoint.y - inset.height

        // Dragging from above the very first line: clamp the LOOKUP point
        // (not the overlap-test bounds themselves) to 0 so the point-based
        // start-fragment lookup below still resolves, rather than bailing
        // out with an empty selection for a perfectly ordinary gesture.
        let lookupPoint = CGPoint(x: minX, y: max(minY, 0))
        let documentStart = contentStorage.documentRange.location
        guard let startFragment = layoutManager.textLayoutFragment(for: lookupPoint) else { return nil }

        var ranges: [NSRange] = []
        var primaryIndex = 0
        var bestPrimaryDistance = CGFloat.greatestFiniteMagnitude

        layoutManager.enumerateTextLayoutFragments(
            from: startFragment.rangeInElement.location,
            options: [.ensuresLayout]
        ) { fragment in
            let fragmentFrame = fragment.layoutFragmentFrame
            guard fragmentFrame.minY < maxY else { return false }
            guard fragmentFrame.maxY > minY else { return true }
            let fragmentOffset = contentStorage.offset(from: documentStart, to: fragment.rangeInElement.location)

            for lineFragment in fragment.textLineFragments {
                let lineMinY = fragmentFrame.minY + lineFragment.typographicBounds.minY
                let lineMaxY = lineMinY + lineFragment.typographicBounds.height
                guard lineMinY < maxY, lineMaxY > minY else { continue }

                // Assumes every wrapped line's own local x=0 coincides with
                // `fragmentFrame.minX` — true today (confirmed by the same
                // probe cited above) because this codebase applies no
                // paragraph styling beyond `lineHeightMultiple` anywhere
                // (`EditorTextSystem.swift`'s `typingAttributes`) — no
                // indent, alignment, or RTL writing direction. Flagged by an
                // independent hostile review of this slice as real, current
                // fragility rather than a live bug: a future hanging indent
                // (e.g. for blockquotes) or RTL paragraph support would need
                // this reworked to account for each line's own indent/writing
                // direction rather than always subtracting the fragment's own
                // `minX`.
                let localMinX = minX - fragmentFrame.minX
                let localMaxX = maxX - fragmentFrame.minX
                let localY = lineFragment.typographicBounds.height / 2
                let startLocal = lineFragment.characterIndex(for: CGPoint(x: localMinX, y: localY))
                let endLocal = lineFragment.characterIndex(for: CGPoint(x: localMaxX, y: localY))
                let location = fragmentOffset + min(startLocal, endLocal)
                let length = max(startLocal, endLocal) - min(startLocal, endLocal)
                ranges.append(NSRange(location: location, length: length))

                let lineCenterDistance = abs((lineMinY + lineMaxY) / 2 - targetY)
                if lineCenterDistance < bestPrimaryDistance {
                    bestPrimaryDistance = lineCenterDistance
                    primaryIndex = ranges.count - 1
                }
            }
            return true
        }
        guard !ranges.isEmpty else { return nil }
        return (ranges, primaryIndex)
    }
}
