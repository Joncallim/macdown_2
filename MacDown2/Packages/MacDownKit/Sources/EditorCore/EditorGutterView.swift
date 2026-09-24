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
        // epic-22-implementation.md §12: new UI ships with basic
        // accessibility labels/identifiers from the same slice that
        // introduces it, not deferred to a later cleanup pass.
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(String(localized: "Line numbers", bundle: .module))
        setAccessibilityIdentifier("editorGutter")
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
        let digitWidth = Self.widestDigitWidth(in: font)
        let needed = digitWidth * CGFloat(digitCount) + Self.horizontalPadding * 2
        let newThickness = max(Self.minimumThickness, needed.rounded(.up))
        guard newThickness != ruleThickness else {
            needsDisplay = true
            return
        }
        ruleThickness = newThickness
        needsDisplay = true
    }

    /// The widest "0"..."9" glyph in `font`. The editor's font picker offers
    /// every installed font family via `NSFontManager.availableFontFamilies`
    /// (`DocumentEditorSplitView+AppSettings.swift`), not just monospace
    /// ones, so a proportional or display font could render some other
    /// digit wider than "0" — measuring only "0" risks clipping labels'
    /// left edge once the line count needs that wider digit.
    private static func widestDigitWidth(in font: NSFont) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        return "0123456789".reduce(CGFloat(0)) { widest, digit in
            max(widest, (String(digit) as NSString).size(withAttributes: attributes).width)
        }
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
