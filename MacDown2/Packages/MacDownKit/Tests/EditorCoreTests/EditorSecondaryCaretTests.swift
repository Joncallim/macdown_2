import AppKit
@testable import EditorCore
import Foundation
import Testing

/// EPIC-22 Slice 3b-i — the multi-caret rendering foundation §6.10
/// designed: every caret beyond the primary one lives only in
/// `EditorTextSystem.selectionSet` (never `textView.selectedRanges`, which
/// cannot represent it — §6.9's architecture-correction note), so
/// `EditorTextView` draws it itself. Mirrors `EditorTextViewTests`'
/// established real-mount, offscreen-render, pixel-sampling technique
/// (`NSImage(size:flipped:drawingHandler:)`, "dominant channel" color
/// matching rather than exact-color matching, since macOS font-smoothing
/// measurably shifts a small glyph/fill's rendered color).
@MainActor
@Suite("EditorTextView secondary carets (Slice 3b-i)")
struct EditorSecondaryCaretTests {
    private struct Mounted {
        let system: EditorTextSystem
        let textView: EditorTextView
        let window: NSWindow
    }

    private func mount(
        text: String,
        frame: NSRect = NSRect(x: 0, y: 0, width: 200, height: 80)
    ) throws -> Mounted {
        let system = EditorTextSystem(identity: UUID().uuidString, initialText: text, configuration: .default)
        let textView = try #require(system.textView as? EditorTextView)
        let scrollView = NSScrollView(frame: frame)
        scrollView.documentView = textView
        system.scrollView = scrollView
        textView.frame = frame
        textView.backgroundColor = .white
        textView.textColor = .black
        textView.insertionPointColor = NSColor(red: 1, green: 0, blue: 0, alpha: 1)

        let window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = scrollView
        window.makeKeyAndOrderFront(nil)
        return Mounted(system: system, textView: textView, window: window)
    }

    /// See `EditorTextViewTests.render(_:dirtyRect:)`'s doc comment for why
    /// `NSImage(size:flipped:drawingHandler:)` is the correct technique here
    /// (a hand-built bitmap context does not auto-flip; `cacheDisplay`
    /// unreliably captures `draw(_:)`'s output for a layer-backed view).
    private func render(_ textView: EditorTextView, dirtyRect: NSRect? = nil) throws -> NSBitmapImageRep {
        let bounds = textView.bounds
        let rectToDraw = dirtyRect ?? bounds
        let image = NSImage(size: bounds.size, flipped: true) { _ in
            textView.draw(rectToDraw)
            return true
        }
        var proposedRect = NSRect(origin: .zero, size: bounds.size)
        let cgImage = try #require(image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil))
        return NSBitmapImageRep(cgImage: cgImage)
    }

    /// See `EditorTextViewTests.countRedDominantPixels(in:)`'s doc comment.
    private func countRedDominantPixels(in bitmap: NSBitmapImageRep) -> Int {
        var count = 0
        for pixelX in 0 ..< bitmap.pixelsWide {
            for pixelY in 0 ..< bitmap.pixelsHigh {
                guard let pixel = bitmap.colorAt(x: pixelX, y: pixelY)?.usingColorSpace(.deviceRGB) else { continue }
                if pixel.redComponent - max(pixel.greenComponent, pixel.blueComponent) > 0.3 {
                    count += 1
                }
            }
        }
        return count
    }

    @Test func drawsASecondaryCaretWhenTheSelectionSetHoldsAnUnrepresentableBareCaret() throws {
        let mounted = try mount(text: "cat cat cat")
        defer { mounted.window.orderOut(nil) }

        // A primary caret at 3, plus a secondary bare caret at 11 --
        // `textView.selectedRanges` can only ever show the primary (§6.9),
        // so this exercises exactly the case `EditorTextSystem.selectionSet`'s
        // getter/setter (Slice 3b-i's own fix) needs to retain correctly.
        mounted.system.selectionSet = EditorSelectionSet(
            ranges: [NSRange(location: 3, length: 0), NSRange(location: 11, length: 0)],
            primaryIndex: 0
        )
        #expect(mounted.system.selectionSet.isMultiple, "the fixture itself must actually hold two carets")
        #expect(mounted.system.textView.selectedRanges.map(\.rangeValue) == [NSRange(location: 3, length: 0)])

        let bitmap = try render(mounted.textView)
        #expect(
            countRedDominantPixels(in: bitmap) > 0,
            "expected a drawn indicator for the secondary caret AppKit itself cannot represent"
        )
    }

    @Test func drawsNothingExtraWithOnlyASingleCaretActive() throws {
        let mounted = try mount(text: "cat cat cat")
        defer { mounted.window.orderOut(nil) }
        mounted.system.selectedRange = NSRange(location: 3, length: 0)

        let bitmap = try render(mounted.textView)
        #expect(countRedDominantPixels(in: bitmap) == 0, "no secondary-caret pixels should appear for a single caret")
    }

    @Test func drawsNothingExtraForARealNonTouchingMultiSelectionWithNoBareCarets() throws {
        // Slice 3a's own achievable case (multiple real, non-zero-length
        // selections) round-trips through `textView.selectedRanges`
        // correctly and has no bare secondary caret to draw -- this pass
        // must not paint anything extra over an ordinary multi-selection.
        let mounted = try mount(text: "cat cat cat")
        defer { mounted.window.orderOut(nil) }
        mounted.system.selectionSet = EditorSelectionSet(
            ranges: [NSRange(location: 0, length: 3), NSRange(location: 8, length: 3)],
            primaryIndex: 0
        )

        let bitmap = try render(mounted.textView)
        #expect(countRedDominantPixels(in: bitmap) == 0)
    }

    @Test func drawsASecondaryCaretForAScrolledPartialRedraw() throws {
        // Mirrors `EditorTextViewTests.drawsMarkersCorrectlyForAScrolledPartialRedrawWithANonzeroTextContainerInset`:
        // `firstRect(forCharacterRange:actualRange:)` is independent of
        // `dirtyRect`, unlike the invisibles pass, but this confirms the
        // draw call itself still fires (and is not accidentally gated on
        // `dirtyRect`'s origin) for a genuinely scrolled/partial redraw.
        let mounted = try mount(text: "cat cat cat", frame: NSRect(x: 0, y: 0, width: 200, height: 100))
        defer { mounted.window.orderOut(nil) }
        mounted.system.selectionSet = EditorSelectionSet(
            ranges: [NSRange(location: 3, length: 0), NSRange(location: 11, length: 0)],
            primaryIndex: 0
        )

        let scrolledDirtyRect = NSRect(x: 0, y: 20, width: 200, height: 40)
        let bitmap = try render(mounted.textView, dirtyRect: scrolledDirtyRect)
        #expect(countRedDominantPixels(in: bitmap) > 0)
    }

    @Test func aHundredSecondaryCaretsStayWithinAReasonableDrawBudget() throws {
        // §11/§15's "100+ simultaneous cursors" stress case, applied to
        // this pass specifically: `drawSecondaryCarets()` calls
        // `firstRect(forCharacterRange:actualRange:)` once per secondary
        // caret rather than pre-filtering to the viewport (§6.10's own
        // documented, measured-not-guessed decision) -- this confirms that
        // choice is actually fine at this scale rather than assuming it.
        let lines = (1 ... 200).map { "line \($0)" }
        let text = lines.joined(separator: "\n")
        let mounted = try mount(text: text, frame: NSRect(x: 0, y: 0, width: 300, height: 400))
        defer { mounted.window.orderOut(nil) }

        let lineIndex = mounted.system.lineIndex
        var ranges: [NSRange] = []
        for line in 1 ... 100 {
            let offset = lineIndex.utf16Offset(forLine: line, column: 1, in: text as NSString)
            ranges.append(NSRange(location: offset, length: 0))
        }
        mounted.system.selectionSet = EditorSelectionSet(ranges: ranges, primaryIndex: 0)

        let start = Date()
        _ = try render(mounted.textView)
        let elapsed = Date().timeIntervalSince(start)
        #expect(elapsed < 1.0, "drawing 100 secondary carets took \(elapsed)s, expected well under 1s")
    }
}
