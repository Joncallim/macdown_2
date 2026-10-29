import AppKit
@testable import EditorCore
import Foundation
import Testing

@MainActor
@Suite("Current editor line")
struct EditorCurrentLinePresentationTests {
    @Test func followsThePrimarySelectionAcrossMixedLineEndings() {
        let source = "😀 first\r\nsecond\rthird\nlast"
        let system = EditingAssistIntegrationSupport.makeSystem(text: source)
        let text = source as NSString
        let second = text.range(of: "second").location
        let third = text.range(of: "third").location
        let last = text.range(of: "last").location

        system.selectionSet = EditorSelectionSet(ranges: [
            NSRange(location: 0, length: 0),
            NSRange(location: third, length: 0),
        ], primaryIndex: 1)
        #expect(system.currentLogicalLine == 3)

        system.selectionSet = EditorSelectionSet(single: NSRange(location: second, length: 0))
        #expect(system.currentLogicalLine == 2)
        system.selectionSet = EditorSelectionSet(single: NSRange(location: last, length: 0))
        #expect(system.currentLogicalLine == 4)
    }

    @Test func activeGutterLabelHasAWeightCue() {
        let regular = NSFont.systemFont(ofSize: 14, weight: .regular)
        let active = EditorGutterView.activeLineFont(for: regular)
        #expect(active.fontDescriptor.symbolicTraits.contains(.bold))
        #expect(active.pointSize == regular.pointSize)
    }

    @Test func paintsTheActiveLineBehindTextInAScrolledDirtyRegion() throws {
        var configuration = EditorConfiguration.default
        configuration.textInsets = NSSize(width: 4, height: 30)
        configuration.scrollsPastEnd = false
        let source = (1 ... 50).map { "line \($0)" }.joined(separator: "\n")
        let system = EditorTextSystem(identity: UUID().uuidString, initialText: source, configuration: configuration)
        let textView = try #require(system.textView as? EditorTextView)
        let frame = NSRect(x: 0, y: 0, width: 300, height: 400)
        let scrollView = NSScrollView(frame: frame)
        scrollView.documentView = textView
        system.scrollView = scrollView
        textView.frame = NSRect(x: 0, y: 0, width: frame.width, height: 1200)
        textView.backgroundColor = .white
        textView.textColor = .black
        let window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.animationBehavior = .none
        window.contentView = scrollView
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }

        let fifteenth = (source as NSString).range(of: "line 15").location
        system.selectionSet = EditorSelectionSet(single: NSRange(location: fifteenth, length: 0))
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: 250))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        #expect(textView.visibleRect.minY > 0, "the viewport must actually have scrolled")
        let dirty = NSRect(x: 0, y: 280, width: 300, height: 100)
        textView.currentLineColor = .red
        let highlighted = try render(textView, dirty: dirty)
        textView.currentLineColor = .clear
        let unhighlighted = try render(textView, dirty: dirty)

        #expect(redDominantPixels(highlighted) > 0, "the production draw path must paint the active row")
        #expect(redDominantPixels(unhighlighted) == 0, "the red pixels must come from current-line painting")
    }

    @Test func markerDistinguishesTheActiveLineEvenWithABoldEditorFont() throws {
        let system = EditorTextSystem(
            identity: UUID().uuidString,
            initialText: "first\nsecond",
            configuration: .default
        )
        system.textView.font = .boldSystemFont(ofSize: 14)
        system.textView.backgroundColor = .white
        system.textView.textColor = .black
        let frame = NSRect(x: 0, y: 0, width: 300, height: 120)
        let scrollView = NSScrollView(frame: frame)
        scrollView.documentView = system.textView
        system.scrollView = scrollView
        system.textView.frame = frame
        let gutter = EditorGutterView(scrollView: scrollView, system: system)
        scrollView.verticalRulerView = gutter
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        let window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.animationBehavior = .none
        window.contentView = scrollView
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }

        var baselines: [CGFloat] = []
        system.enumerateVisibleLineFragments { _, baseline in baselines.append(baseline) }
        let secondBaseline = try #require(baselines.dropFirst().first)
        let viewBaseline = gutter.convert(
            NSPoint(x: 0, y: secondBaseline + system.textView.textContainerInset.height),
            from: system.textView
        ).y
        let font = try #require(system.textView.font)
        let markerBand = Int(viewBaseline - font.ascender) ..< Int(viewBaseline + 1)

        system.selectionSet = EditorSelectionSet(single: NSRange(location: 0, length: 0))
        let inactive = try renderGutter(gutter)
        system.selectionSet = EditorSelectionSet(single: NSRange(location: 6, length: 0))
        let active = try renderGutter(gutter)
        let scaleX = CGFloat(active.pixelsWide) / gutter.bounds.width
        let scaleY = CGFloat(active.pixelsHigh) / gutter.bounds.height
        let markerColumns = 0 ..< Int((gutter.bounds.width - 16) * scaleX)
        let markerRows = Int(CGFloat(markerBand.lowerBound) * scaleY)
            ..< Int(CGFloat(markerBand.upperBound) * scaleY)

        #expect(markerInk(in: active, columns: markerColumns, rows: markerRows) > 0)
        #expect(markerInk(in: inactive, columns: markerColumns, rows: markerRows) == 0)
    }

    private func renderGutter(_ gutter: EditorGutterView) throws -> NSBitmapImageRep {
        let bounds = gutter.bounds
        let image = NSImage(size: bounds.size, flipped: true) { _ in
            gutter.drawHashMarksAndLabels(in: bounds)
            return true
        }
        var proposed = NSRect(origin: .zero, size: bounds.size)
        let pixels = try #require(image.cgImage(forProposedRect: &proposed, context: nil, hints: nil))
        return NSBitmapImageRep(cgImage: pixels)
    }

    private func markerInk(in bitmap: NSBitmapImageRep, columns: Range<Int>, rows: Range<Int>) -> Int {
        columns.reduce(0) { count, pixelX in
            count + rows.reduce(0) { rowCount, pixelY in
                guard pixelY >= 0, pixelY < bitmap.pixelsHigh,
                      let color = bitmap.colorAt(x: pixelX, y: pixelY)?.usingColorSpace(.deviceRGB)
                else { return rowCount }
                return rowCount + (color.redComponent < 0.5 ? 1 : 0)
            }
        }
    }

    private func render(_ textView: EditorTextView, dirty: NSRect) throws -> NSBitmapImageRep {
        let bounds = textView.bounds
        let image = NSImage(size: bounds.size, flipped: true) { _ in
            textView.draw(dirty)
            return true
        }
        var proposed = NSRect(origin: .zero, size: bounds.size)
        let pixels = try #require(image.cgImage(forProposedRect: &proposed, context: nil, hints: nil))
        return NSBitmapImageRep(cgImage: pixels)
    }

    private func redDominantPixels(_ bitmap: NSBitmapImageRep) -> Int {
        var count = 0
        for pixelX in 0 ..< bitmap.pixelsWide {
            for pixelY in 0 ..< bitmap.pixelsHigh {
                guard let color = bitmap.colorAt(x: pixelX, y: pixelY)?.usingColorSpace(.deviceRGB)
                else { continue }
                if color.redComponent - max(color.greenComponent, color.blueComponent) > 0.3 {
                    count += 1
                }
            }
        }
        return count
    }
}
