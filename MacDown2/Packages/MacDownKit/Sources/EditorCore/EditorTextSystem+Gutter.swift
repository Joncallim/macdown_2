import AppKit

public extension EditorTextSystem {
    /// Enumerates `(utf16Offset, minY)` for every `NSTextLayoutFragment`
    /// currently materialized in the visible viewport, in top-to-bottom
    /// order, calling `body` for each. Never asks TextKit 2 to lay out
    /// anything beyond the visible rect — mirrors `topVisibleUTF16Offset`'s
    /// existing bounded-lookup discipline and the `<500`-fragments-for-a-
    /// 10 MB-document budget `EditorPerformanceTests.open10MBLazy` pins.
    /// Powers the line-number gutter; a naive whole-document walk of
    /// `lineIndex.lineStartOffsets` to place `lineCount` labels would
    /// violate that same discipline for a large file.
    func enumerateVisibleLineFragments(_ body: (_ utf16Offset: Int, _ minY: CGFloat) -> Void) {
        guard let scrollView else { return }
        let visibleRect = scrollView.contentView.bounds
        let topPoint = textView.convert(visibleRect.origin, from: scrollView.contentView)
        let bottomPoint = textView.convert(
            NSPoint(x: visibleRect.origin.x, y: visibleRect.maxY),
            from: scrollView.contentView
        )
        guard let startFragment = layoutManager.textLayoutFragment(for: topPoint) else { return }

        let documentStart = contentStorage.documentRange.location
        layoutManager.enumerateTextLayoutFragments(
            from: startFragment.rangeInElement.location,
            options: [.ensuresLayout]
        ) { fragment in
            let frame = fragment.layoutFragmentFrame
            guard frame.minY < bottomPoint.y else { return false }
            let offset = contentStorage.offset(from: documentStart, to: fragment.rangeInElement.location)
            body(offset, frame.minY)
            return true
        }
    }
}
