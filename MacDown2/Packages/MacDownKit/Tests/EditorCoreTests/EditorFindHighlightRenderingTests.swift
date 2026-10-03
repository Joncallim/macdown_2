import AppKit
@testable import EditorCore
import Foundation
import Testing

/// Review pass 1: Find highlights were never visible (the background fill painted over
/// them) and were drawn at the wrong place (paragraph-local line-fragment ranges were
/// compared with document offsets).
@MainActor
@Suite("Find highlight rendering")
struct EditorFindHighlightRenderingTests {
    private struct Mounted {
        let system: EditorTextSystem
        let textView: EditorTextView
        let window: NSWindow
    }

    private func mount(text: String) throws -> Mounted {
        let frame = NSRect(x: 0, y: 0, width: 400, height: 200)
        var configuration = EditorConfiguration.default
        configuration.scrollsPastEnd = false
        let system = EditorTextSystem(identity: UUID().uuidString, initialText: text, configuration: configuration)
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
        let image = NSImage(size: bounds.size, flipped: true) { _ in
            textView.draw(bounds)
            return true
        }
        var proposed = NSRect(origin: .zero, size: bounds.size)
        let cgImage = try #require(image.cgImage(forProposedRect: &proposed, context: nil, hints: nil))
        return NSBitmapImageRep(cgImage: cgImage)
    }

    /// Pixel rows (by row index) that contain highlight-coloured pixels.
    private func highlightedRows(_ bitmap: NSBitmapImageRep) -> [Int] {
        var rows: [Int] = []
        for row in 0 ..< bitmap.pixelsHigh {
            let hasHighlight = (0 ..< bitmap.pixelsWide).contains { column in
                guard let pixel = bitmap.colorAt(x: column, y: row)?.usingColorSpace(.deviceRGB) else { return false }
                return pixel.redComponent > 0.9 && pixel.greenComponent > 0.6 && pixel.blueComponent < 0.85
            }
            if hasHighlight {
                rows.append(row)
            }
        }
        return rows
    }

    private func bands(_ bitmap: NSBitmapImageRep) -> [ClosedRange<Int>] {
        var result: [ClosedRange<Int>] = []
        for row in highlightedRows(bitmap) {
            if let last = result.last, row - last.upperBound <= 3 {
                result[result.count - 1] = last.lowerBound ... row
            } else {
                result.append(row ... row)
            }
        }
        return result
    }

    @Test func aHighlightIsVisibleWithTheDefaultOpaqueBackground() throws {
        let mounted = try mount(text: "foo\nbbb\nccc\nxxx")
        defer { mounted.window.orderOut(nil) }
        mounted.system.setFindHighlights(ranges: [NSRange(location: 0, length: 3)], currentIndex: 0)
        #expect(
            try !highlightedRows(render(mounted.textView)).isEmpty,
            "highlight must be visible with drawsBackground = true"
        )
    }

    @Test func aMatchOnTheThirdLineIsDrawnOnTheThirdLineOnly() throws {
        let mounted = try mount(text: "aaa\nbbb\nfoo bar\nxxx")
        defer { mounted.window.orderOut(nil) }
        mounted.system.setFindHighlights(ranges: [NSRange(location: 8, length: 3)], currentIndex: 0)
        let found = try bands(render(mounted.textView))
        #expect(found.count == 1)
        // Line 3 sits below lines 1 and 2: its band starts well below the top of the view.
        #expect((found.first?.lowerBound ?? 0) > 70, "match on line 3 must be drawn on line 3: \(found)")
    }

    @Test func aMatchAtOffsetZeroIsDrawnOnTheFirstLineOnly() throws {
        let mounted = try mount(text: "foo\nbbb\nccc\nxxx")
        defer { mounted.window.orderOut(nil) }
        mounted.system.setFindHighlights(ranges: [NSRange(location: 0, length: 3)], currentIndex: 0)
        #expect(try bands(render(mounted.textView)).count == 1)
    }
}
