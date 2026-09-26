import AppKit

/// Viewport-bounded Find match highlighting (EPIC-22 §6.14, Slice 5a).
/// Extracted from `EditorTextView.swift` to stay under its file-length
/// budget, matching the established per-drawing-pass extraction convention
/// (e.g. `EditorTextSystem+CommentToggle.swift`).
extension EditorTextView {
    /// Follows exactly the same bounded `enumerateTextLayoutFragments` walk
    /// and `textContainerInset` coordinate conversion `drawInvisibles`
    /// (`EditorTextView.swift`) already established — and was
    /// hostile-review-corrected for in PR #127, see that method's own doc
    /// comment — rather than re-deriving the geometry math independently:
    /// match count is unbounded (every occurrence in a document that could
    /// be many MB), so this must never touch layout outside the visible
    /// dirty rect. Drawn BEFORE `super.draw(_:)` in `draw(_:)` so the
    /// highlight sits behind the glyphs, like every comparable editor's own
    /// find highlighting, rather than obscuring the matched text.
    func drawFindHighlights(in dirtyRect: NSRect, layoutManager: NSTextLayoutManager) {
        guard !findHighlightRanges.isEmpty else { return }
        let inset = textContainerInset
        let containerOrigin = CGPoint(x: dirtyRect.origin.x - inset.width, y: dirtyRect.origin.y - inset.height)
        guard let startFragment = layoutManager.textLayoutFragment(for: containerOrigin) else { return }
        let containerDirtyMinY = dirtyRect.minY - inset.height
        let containerDirtyMaxY = dirtyRect.maxY - inset.height
        let currentMatchColor = NSColor.systemOrange.withAlphaComponent(0.55)
        let otherMatchColor = NSColor.systemYellow.withAlphaComponent(0.35)

        // `findHighlightRanges` comes straight from `TextSearchEngine.matches`,
        // which always returns matches in ascending document order (both its
        // literal path, which scans forward via repeated `NSString.range(of:)`,
        // and its regex path, which is `NSRegularExpression.enumerateMatches`'s
        // own documented left-to-right order) — and `enumerateTextLayoutFragments`
        // likewise walks fragments top-to-bottom in ascending document order.
        // `matchCursor` is a single forward-only pointer shared across every
        // visible line fragment: since neither sequence ever goes backward,
        // once a match's own END falls behind the CURRENT line's start it can
        // never be relevant to this or any LATER line, so it is permanently
        // skipped rather than re-checked against every subsequent line. A
        // post-review fix: the original version re-scanned the ENTIRE match
        // array per visible line (O(visible lines × total match count)),
        // which the file's own original doc comment already flagged as a
        // risk it hadn't actually addressed — match count is unbounded
        // (every occurrence in a document that could be many MB), so a
        // short, frequent query made every scroll/redraw pass measurably
        // slower even though layout itself stayed correctly viewport-bounded.
        var matchCursor = 0

        layoutManager.enumerateTextLayoutFragments(
            from: startFragment.rangeInElement.location,
            options: [.ensuresLayout]
        ) { fragment in
            let fragmentFrame = fragment.layoutFragmentFrame
            guard fragmentFrame.minY < containerDirtyMaxY else { return false }
            guard fragmentFrame.maxY > containerDirtyMinY else { return true }

            for lineFragment in fragment.textLineFragments {
                let lineRange = lineFragment.characterRange
                while matchCursor < findHighlightRanges.count,
                      findHighlightRanges[matchCursor].location + findHighlightRanges[matchCursor].length
                      <= lineRange.location {
                    matchCursor += 1
                }
                var index = matchCursor
                while index < findHighlightRanges.count, findHighlightRanges[index].location < lineRange.upperBound {
                    defer { index += 1 }
                    let matchRange = findHighlightRanges[index]
                    guard let intersection = lineRange.intersection(matchRange), intersection.length > 0 else {
                        continue
                    }
                    let startPoint = lineFragment.locationForCharacter(at: intersection.location)
                    let endPoint = lineFragment.locationForCharacter(at: intersection.location + intersection.length)
                    let rect = NSRect(
                        x: fragmentFrame.minX + startPoint.x + inset.width,
                        y: fragmentFrame.minY + lineFragment.typographicBounds.minY + inset.height,
                        width: max(endPoint.x - startPoint.x, 1),
                        height: lineFragment.typographicBounds.height
                    )
                    let color = index == currentFindMatchIndex ? currentMatchColor : otherMatchColor
                    color.setFill()
                    NSBezierPath(rect: rect).fill()
                }
            }
            return true
        }
    }
}
