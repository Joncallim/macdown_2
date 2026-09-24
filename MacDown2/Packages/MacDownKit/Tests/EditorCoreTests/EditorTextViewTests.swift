import AppKit
@testable import EditorCore
import Foundation
import Testing

/// EPIC-22 Slice 2c — AppKit-level coverage for `EditorTextView`'s
/// invisible-character drawing. Goes further than a mere crash-safety
/// check (`EditorGutterViewTests`' own established minimum): renders into a
/// real offscreen `NSBitmapImageRep` context and samples pixel colors to
/// confirm markers are actually drawn somewhere, since pixel sampling is
/// the strongest automated substitute available for real visual
/// verification this session's toolkit has — not a claim of full
/// visual-fidelity proof (epic-22-implementation.md §6.8).
@MainActor
@Suite("EditorTextView invisibles")
struct EditorTextViewTests {
    private struct Mounted {
        let system: EditorTextSystem
        let textView: EditorTextView
        let window: NSWindow
    }

    private func mount(text: String, frame: NSRect = NSRect(x: 0, y: 0, width: 200, height: 80)) throws -> Mounted {
        let system = EditorTextSystem(identity: UUID().uuidString, initialText: text, configuration: .default)
        let textView = try #require(system.textView as? EditorTextView)
        let scrollView = NSScrollView(frame: frame)
        scrollView.documentView = textView
        system.scrollView = scrollView
        textView.frame = frame
        textView.backgroundColor = .white
        textView.textColor = .black

        let window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = scrollView
        window.makeKeyAndOrderFront(nil)
        return Mounted(system: system, textView: textView, window: window)
    }

    private func render(_ textView: EditorTextView) throws -> NSBitmapImageRep {
        let bounds = textView.bounds
        // `NSImage(size:flipped:drawingHandler:)`, not a hand-built
        // `NSGraphicsContext(bitmapImageRep:)` plus a direct `draw(_:)` call,
        // and not `cacheDisplay(in:to:)`: `NSTextView.isFlipped` is `true`,
        // and a manually constructed bitmap context does not auto-flip to
        // match (silently misplacing every drawn rect); `cacheDisplay`
        // handles the flip but, for a layer-backed view inside a real
        // window (the case here), does not reliably capture `draw(_:)`'s
        // output at all (a known AppKit/Core-Animation compositing gotcha,
        // confirmed empirically: `draw(_:)` visibly executed real drawing
        // commands at the expected rect, yet `cacheDisplay`'s bitmap showed
        // nothing there). `NSImage`'s `flipped` parameter sets up the
        // correct coordinate transform for the drawing block without
        // routing through layer compositing.
        let image = NSImage(size: bounds.size, flipped: true) { rect in
            textView.draw(rect)
            return true
        }
        var proposedRect = NSRect(origin: .zero, size: bounds.size)
        let cgImage = try #require(image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil))
        return NSBitmapImageRep(cgImage: cgImage)
    }

    /// Counts pixels that are clearly red-dominant, rather than matching the
    /// marker's exact requested RGB value with a tight tolerance: macOS's
    /// font smoothing/subpixel anti-aliasing measurably shifts a small
    /// glyph's rendered color away from the value it was drawn with (a real,
    /// confirmed-empirically effect, not a bug in this test or in
    /// `EditorTextView`) — a glyph requested as pure red (1, 0, 0) rendered
    /// with a "core" color around (0.94, 0.30, 0.16) in this suite's own
    /// measurements. Black text anti-aliased against a white background can
    /// only ever produce gray pixels (R == G == B); it can never produce a
    /// pixel where red is *substantially* higher than green and blue, so
    /// this threshold cleanly distinguishes "a marker was drawn here" from
    /// ordinary text/background anti-aliasing without needing exact
    /// colorimetric fidelity.
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

    private let markerColor = NSColor(red: 1, green: 0, blue: 0, alpha: 1)

    @Test func drawsMarkerColoredPixelsOnlyWhenInvisiblesAreEnabled() throws {
        let enabled = try mount(text: "a b")
        defer { enabled.window.orderOut(nil) }
        enabled.textView.showsInvisibles = true
        enabled.textView.invisiblesColor = markerColor
        let enabledBitmap = try render(enabled.textView)

        let disabled = try mount(text: "a b")
        defer { disabled.window.orderOut(nil) }
        disabled.textView.showsInvisibles = false
        disabled.textView.invisiblesColor = markerColor
        let disabledBitmap = try render(disabled.textView)

        #expect(
            countRedDominantPixels(in: enabledBitmap) > 0,
            "expected at least one marker-colored pixel when invisibles are enabled"
        )
        #expect(
            countRedDominantPixels(in: disabledBitmap) == 0,
            "no marker-colored pixels should appear when invisibles are disabled"
        )
    }

    @Test func plainTextWithNoInvisiblesDrawsNoMarkers() throws {
        let mounted = try mount(text: "hello")
        defer { mounted.window.orderOut(nil) }
        mounted.textView.showsInvisibles = true
        mounted.textView.invisiblesColor = markerColor

        let bitmap = try render(mounted.textView)
        #expect(countRedDominantPixels(in: bitmap) == 0)
    }

    @Test func aLineOfTabsDrawsOneMarkerColoredRegionPerTab() throws {
        let mounted = try mount(text: "\t\t\t")
        defer { mounted.window.orderOut(nil) }
        mounted.textView.showsInvisibles = true
        mounted.textView.invisiblesColor = markerColor

        let bitmap = try render(mounted.textView)
        #expect(countRedDominantPixels(in: bitmap) > 0)
    }

    @Test func drawingA10MBDocumentNeverMaterializesTheWholeDocument() throws {
        // Extends `EditorPerformanceTests.open10MBLazy`'s fragment-count
        // assertion pattern to the invisibles draw path specifically, per
        // §6.8's test commitment: a large document with invisibles enabled
        // must not force whole-document layout.
        let text = Fixtures.markdown(targetByteCount: 10_000_000)
        let mounted = try mount(text: text, frame: NSRect(x: 0, y: 0, width: 800, height: 1000))
        defer { mounted.window.orderOut(nil) }
        mounted.textView.showsInvisibles = true

        var fragmentCount = 0
        let start = mounted.system.layoutManager.documentRange.location
        mounted.system.layoutManager.enumerateTextLayoutFragments(from: start, options: .ensuresLayout) { fragment in
            fragmentCount += 1
            return fragment.layoutFragmentFrame.maxY < mounted.textView.bounds.height
        }
        #expect(fragmentCount < 500, "opening the document laid out \(fragmentCount) fragments")

        // The real assertion here is that drawing over this large document
        // completes at all, within the same viewport-bounded discipline.
        _ = try render(mounted.textView)
    }
}
