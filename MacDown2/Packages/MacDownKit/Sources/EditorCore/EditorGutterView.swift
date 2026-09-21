import AppKit

/// Line-number gutter for the editor's `NSScrollView`, backed by
/// `EditorTextSystem.lineIndex` and `enumerateVisibleLineFragments(_:)`.
/// Draws only the currently visible, already-laid-out lines — never walks
/// the whole document — per epic-22-implementation.md §6.6's
/// viewport-laziness contract. A wrapped logical line's continuation
/// fragments are skipped by `EditorGutterLayout`, so only the fragment
/// that actually starts a logical line gets a number.
@MainActor
public final class EditorGutterView: NSRulerView {
    private weak var system: EditorTextSystem?

    private static let horizontalPadding: CGFloat = 6
    private static let minimumThickness: CGFloat = 32

    public init(scrollView: NSScrollView, system: EditorTextSystem) {
        self.system = system
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = system.textView
        updateThickness()
    }

    @available(*, unavailable)
    public required init(coder _: NSCoder) {
        fatalError("EditorGutterView does not support NSCoder")
    }

    /// Recomputes `ruleThickness` from the document's current digit count
    /// and marks the ruler for redraw. Call after any edit that could grow
    /// or shrink the line count (a 9-to-10-line, or 99-to-100-line, change
    /// needs one more/fewer digit of width) and after font changes.
    public func updateThickness() {
        guard let system else { return }
        let digitCount = String(max(1, system.lineIndex.lineCount)).count
        let font = system.textView.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let digitWidth = ("0" as NSString).size(withAttributes: [.font: font]).width
        let needed = digitWidth * CGFloat(digitCount) + Self.horizontalPadding * 2
        let newThickness = max(Self.minimumThickness, needed.rounded(.up))
        guard newThickness != ruleThickness else {
            needsDisplay = true
            return
        }
        ruleThickness = newThickness
        needsDisplay = true
    }

    override public func drawHashMarksAndLabels(in _: NSRect) {
        guard let system else { return }
        let font = system.textView.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let textColor = system.textView.textColor?.withAlphaComponent(0.5) ?? .secondaryLabelColor
        system.textView.backgroundColor.setFill()
        bounds.fill()

        var fragments: [(utf16Offset: Int, minY: CGFloat)] = []
        system.enumerateVisibleLineFragments { offset, minY in
            fragments.append((offset, minY))
        }
        let labels = EditorGutterLayout.labels(for: fragments, lineIndex: system.lineIndex)

        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
        let insetTop = system.textView.textContainerInset.height
        for label in labels {
            let string = String(label.lineNumber) as NSString
            let size = string.size(withAttributes: attributes)
            let convertedOrigin = convert(NSPoint(x: 0, y: label.minY + insetTop), from: system.textView)
            let rect = NSRect(
                x: bounds.width - size.width - Self.horizontalPadding,
                y: convertedOrigin.y,
                width: size.width,
                height: size.height
            )
            string.draw(in: rect, withAttributes: attributes)
        }
    }
}
