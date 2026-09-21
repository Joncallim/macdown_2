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
}
