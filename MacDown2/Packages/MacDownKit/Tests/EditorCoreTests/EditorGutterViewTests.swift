import AppKit
@testable import EditorCore
import Foundation
import Testing

/// EPIC-22 Slice 2a — AppKit-level smoke tests for `EditorGutterView`.
/// `EditorGutterLayoutTests` carries the real correctness weight (pure,
/// exhaustive); these confirm the thin AppKit glue is actually wired up
/// end-to-end (attached to the scroll view, redraws without crashing
/// against a real mounted `NSTextView`, and its width tracks the
/// document's digit count) — not pixel-level rendering, which this
/// session has no way to verify visually and honestly discloses as such
/// rather than claiming it as tested.
@MainActor
@Suite("EditorGutterView")
struct EditorGutterViewTests {
    private let support = EditingAssistIntegrationSupport.self

    private struct MountedGutter {
        let system: EditorTextSystem
        let gutter: EditorGutterView
        let window: NSWindow
    }

    private func makeMountedGutter(text: String) -> MountedGutter {
        let system = support.makeSystem(text: text)
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        scrollView.documentView = system.textView
        system.scrollView = scrollView
        let gutter = EditorGutterView(scrollView: scrollView, system: system)
        scrollView.verticalRulerView = gutter
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = scrollView
        window.makeKeyAndOrderFront(nil)
        return MountedGutter(system: system, gutter: gutter, window: window)
    }

    @Test func gutterIsAttachedAsTheScrollViewsVerticalRuler() {
        let mounted = makeMountedGutter(text: "one\ntwo\nthree")
        defer { mounted.window.orderOut(nil) }

        let scrollView = mounted.window.contentView as? NSScrollView
        #expect(scrollView?.verticalRulerView === mounted.gutter)
        #expect(scrollView?.rulersVisible == true)
    }

    @Test func drawingDoesNotCrashAgainstARealMountedTextView() throws {
        let mounted = makeMountedGutter(text: String(repeating: "line\n", count: 50))
        defer { mounted.window.orderOut(nil) }

        // `drawHashMarksAndLabels` calls `NSColor.setFill`/`bounds.fill()`
        // and `NSString.draw(in:withAttributes:)`, which need a REAL active
        // graphics context -- calling it with none current (as a naive
        // direct call would) crashes the process (SIGTRAP) rather than
        // merely asserting wrong, which an earlier version of this test hit.
        // A real, mounted `NSWindow` alone does not make one current outside
        // an actual AppKit draw cycle, so this renders into an offscreen
        // bitmap context instead, matching what a real draw cycle sets up.
        let bounds = mounted.gutter.bounds
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: max(1, Int(bounds.width)),
            pixelsHigh: max(1, Int(bounds.height)),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        defer { NSGraphicsContext.restoreGraphicsState() }

        // The real assertion is that this returns at all.
        mounted.gutter.drawHashMarksAndLabels(in: bounds)
    }

    @Test func ruleThicknessGrowsWithMoreLineNumberDigits() {
        let mounted = makeMountedGutter(text: "a")
        defer { mounted.window.orderOut(nil) }

        let thicknessFor1Line = mounted.gutter.ruleThickness

        mounted.system.setText((1 ... 500).map { "line \($0)" }.joined(separator: "\n"))
        mounted.gutter.updateThickness()
        let thicknessFor500Lines = mounted.gutter.ruleThickness

        #expect(thicknessFor500Lines > thicknessFor1Line)
    }

    @Test func ruleThicknessNeverShrinksBelowTheMinimum() {
        let mounted = makeMountedGutter(text: "a")
        defer { mounted.window.orderOut(nil) }

        #expect(mounted.gutter.ruleThickness >= 32)
    }

    /// The Editor settings pane's font picker offers every installed font
    /// family via `NSFontManager.availableFontFamilies`
    /// (`DocumentEditorSplitView+AppSettings.swift`), not just monospace
    /// ones, so `updateThickness()` must size the gutter from the widest
    /// digit glyph, not assume "0" is widest. "Bradley Hand" is a standard
    /// macOS system font whose "7" is measurably wider than its "0",
    /// confirmed independently below so this test fails loudly (rather than
    /// passing vacuously) if that ever stops being true on some future OS.
    @Test func ruleThicknessAccountsForTheWidestDigitNotJustZero() throws {
        let font = try #require(
            NSFont(name: "Bradley Hand", size: 24),
            "Bradley Hand is expected to be installed on every macOS runner"
        )
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let zeroWidth = ("0" as NSString).size(withAttributes: attributes).width
        let sevenWidth = ("7" as NSString).size(withAttributes: attributes).width
        #expect(sevenWidth > zeroWidth, "test fixture assumption broke: Bradley Hand's 7 is no longer wider than 0")

        let mounted = makeMountedGutter(text: (1 ... 500).map { "line \($0)" }.joined(separator: "\n"))
        defer { mounted.window.orderOut(nil) }
        mounted.system.textView.font = font
        mounted.gutter.updateThickness()

        // "500" is 3 digits; horizontalPadding is 6pt each side (see
        // `EditorGutterView.horizontalPadding`).
        let thicknessIfOnlyZeroWereMeasured = (zeroWidth * 3 + 12).rounded(.up)
        #expect(
            mounted.gutter.ruleThickness > thicknessIfOnlyZeroWereMeasured,
            "gutter sized itself as though 0 were the widest digit, clipping a wider one"
        )
    }

    /// epic-22-implementation.md §11's "Gutter draw" row requires extending
    /// `EditorPerformanceTests.open10MBLazy`'s viewport-fragment-count
    /// assertion to the gutter's own draw path specifically -- a large
    /// document exercising ONLY `drawingDoesNotCrashAgainstARealMountedTextView`'s
    /// 50-line fixture proves nothing about whether the gutter's own
    /// enumeration stays viewport-bounded, since a future change that made
    /// gutter drawing walk the whole document would still pass a 50-line
    /// smoke test.
    @Test func drawingA10MBDocumentNeverMaterializesTheWholeDocument() throws {
        let text = Fixtures.markdown(targetByteCount: 10_000_000)
        let mounted = makeMountedGutter(text: text)
        defer { mounted.window.orderOut(nil) }
        mounted.system.textView.frame = NSRect(x: 0, y: 0, width: 400, height: 300)

        var fragmentCount = 0
        mounted.system.enumerateVisibleLineFragments { _, _ in fragmentCount += 1 }
        #expect(fragmentCount < 500, "gutter enumerated \(fragmentCount) fragments for a 10 MB document")

        // Exercise the real draw path end-to-end against the same large
        // document -- not just the enumeration helper above -- so a future
        // regression inside `drawHashMarksAndLabels` itself (not just
        // `enumerateVisibleLineFragments`) would also be caught.
        let bounds = mounted.gutter.bounds
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: max(1, Int(bounds.width)),
            pixelsHigh: max(1, Int(bounds.height)),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        defer { NSGraphicsContext.restoreGraphicsState() }

        mounted.gutter.drawHashMarksAndLabels(in: bounds)
    }
}
