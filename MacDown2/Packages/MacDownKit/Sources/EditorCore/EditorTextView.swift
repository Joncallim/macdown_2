import AppKit

/// `NSTextView` subclass that draws TextKit-2-safe invisible characters
/// (spaces, tabs, line endings) directly within the text content area
/// (epic-22-implementation.md §6.8, §17 Slice 2c).
///
/// This is a `draw(_:)` override rather than a separate overlay `NSView`:
/// AppKit already calls `draw(_:)` with a viewport-clamped dirty rect on
/// exactly the right schedule (scroll, edit, initial display), so a second
/// view would need to reinvent that scroll/invalidation synchronization for
/// no benefit. Never touches `layoutManager` (the legacy TextKit 1
/// accessor) — only `textLayoutManager`, the TextKit 2 API.
@MainActor
public final class EditorTextView: NSTextView {
    /// Public: `EditorTextSystem.apply(_:)` sets this from
    /// `EditorConfiguration.showsInvisibles`.
    public var showsInvisibles = false {
        didSet {
            guard showsInvisibles != oldValue else { return }
            needsDisplay = true
        }
    }

    /// Public: the `Highlighting` module's `NeonSyntaxHighlighter.applyChrome(theme:)`
    /// sets this from `Theme.chrome.invisibles`.
    public var invisiblesColor: NSColor = .tertiaryLabelColor {
        didSet {
            guard showsInvisibles else { return }
            needsDisplay = true
        }
    }

    override public func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard showsInvisibles, let textLayoutManager else { return }
        drawInvisibles(in: dirtyRect, layoutManager: textLayoutManager)
    }

    /// Viewport-bounded: starts at the fragment intersecting `dirtyRect`'s
    /// origin and stops as soon as a fragment's frame is entirely below
    /// `dirtyRect`, mirroring `EditorTextSystem+Gutter.swift`'s
    /// `enumerateVisibleLineFragments` and `EditorTextSystem+Scroll.swift`'s
    /// `topVisibleUTF16Offset` — never a whole-document walk.
    private func drawInvisibles(in dirtyRect: NSRect, layoutManager: NSTextLayoutManager) {
        guard let startFragment = layoutManager.textLayoutFragment(for: dirtyRect.origin) else { return }
        let font = font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: invisiblesColor]
        let insetTop = textContainerInset.height

        layoutManager.enumerateTextLayoutFragments(
            from: startFragment.rangeInElement.location,
            options: [.ensuresLayout]
        ) { fragment in
            let fragmentFrame = fragment.layoutFragmentFrame
            guard fragmentFrame.minY < dirtyRect.maxY else { return false }
            guard fragmentFrame.maxY > dirtyRect.minY else { return true }

            for lineFragment in fragment.textLineFragments {
                let lineText = lineFragment.attributedString
                    .attributedSubstring(from: lineFragment.characterRange).string
                for marker in EditorInvisiblesLayout.markers(in: lineText) {
                    let characterIndex = lineFragment.characterRange.location + marker.localUTF16Offset
                    let point = lineFragment.locationForCharacter(at: characterIndex)
                    let glyphString = marker.glyph as NSString
                    let size = glyphString.size(withAttributes: attributes)
                    let rect = NSRect(
                        x: fragmentFrame.minX + point.x,
                        y: fragmentFrame.minY + lineFragment.typographicBounds.minY + insetTop,
                        width: size.width,
                        height: max(size.height, lineFragment.typographicBounds.height)
                    )
                    glyphString.draw(in: rect, withAttributes: attributes)
                }
            }
            return true
        }
    }
}
