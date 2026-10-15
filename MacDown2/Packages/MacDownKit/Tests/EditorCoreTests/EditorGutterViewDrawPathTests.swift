import AppKit
@testable import EditorCore
import Foundation
import Testing

/// Review of the combined tree: `coreTextMatrixKeepsAsymmetricGlyphsUprightInTheFlippedGutter` only exercised the
/// static helper with the test's own renderer, so deleting the `textMatrix` line from `drawHashMarksAndLabels` left
/// every gutter test green. This renders the PRODUCTION draw path into a flipped bitmap (the arrangement AppKit gives
/// a mounted ruler) and compares the second label ("2", an asymmetric glyph) with an upright and an inverted reference.
@MainActor
@Suite("EditorGutterView production draw path")
struct EditorGutterViewDrawPathTests {
    private struct Mask {
        var rows: [[Bool]]
        var height: Int {
            rows.count
        }

        var width: Int {
            rows.first?.count ?? 0
        }
    }

    private func makeBitmap(width: Int, height: Int) throws -> NSBitmapImageRep {
        try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
    }

    private func luma(_ bitmap: NSBitmapImageRep, _ column: Int, _ row: Int) -> CGFloat {
        guard let color = bitmap.colorAt(x: column, y: row)?.usingColorSpace(.deviceRGB) else { return 1 }
        return 0.299 * color.redComponent + 0.587 * color.greenComponent + 0.114 * color.blueComponent
    }

    /// The tight ink bounding box of the SECOND vertical cluster of ink (the "2" label under the "1" label).
    private func secondLabelMask(in bitmap: NSBitmapImageRep, background: CGFloat) -> Mask? {
        let inked: (Int, Int) -> Bool = { column, row in abs(luma(bitmap, column, row) - background) > 0.12 }
        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh
        let rowHasInk = (0 ..< height).map { row in (0 ..< width).contains { inked($0, row) } }
        var clusters: [ClosedRange<Int>] = []
        var start: Int?
        for (row, hasInk) in rowHasInk.enumerated() {
            if hasInk, start == nil {
                start = row
            }
            if !hasInk, let begin = start {
                clusters.append(begin ... row - 1)
                start = nil
            }
        }
        if let begin = start {
            clusters.append(begin ... height - 1)
        }
        guard clusters.count >= 2 else { return nil }
        let band = clusters[1]
        let columns = (0 ..< width).filter { column in band.contains { inked(column, $0) } }
        guard let first = columns.first, let last = columns.last else { return nil }
        return Mask(rows: band.map { row in (first ... last).map { inked($0, row) } })
    }

    /// Ink width of the bottom two rows minus the top two rows. An upright "2" has a wide bottom bar and a narrow
    /// curved
    /// top (positive); a vertically inverted one is the opposite (negative). Robust against anti-aliasing and scale,
    /// unlike a pixel-overlap comparison.
    private func bottomHeaviness(_ mask: Mask) -> Int {
        func width(of rows: ArraySlice<[Bool]>) -> Int {
            rows.map { row in row.filter(\.self).count }.reduce(0, +)
        }
        return width(of: mask.rows.suffix(2)) - width(of: mask.rows.prefix(2))
    }

    @Test func theProductionDrawPathRendersAnUprightSecondLineNumberInTheFlippedGutter() throws {
        let system = EditingAssistIntegrationSupport.makeSystem(text: "one\ntwo")
        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        scrollView.documentView = system.textView
        system.scrollView = scrollView
        let gutter = EditorGutterView(scrollView: scrollView, system: system)
        scrollView.verticalRulerView = gutter
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.animationBehavior = .none
        window.contentView = scrollView
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        #expect(gutter.isFlipped)

        let bounds = gutter.bounds
        let height = max(1, Int(bounds.height))
        let bitmap = try makeBitmap(width: max(1, Int(bounds.width)), height: height)
        let cgContext = try #require(NSGraphicsContext(bitmapImageRep: bitmap)?.cgContext)
        cgContext.translateBy(x: 0, y: CGFloat(height))
        cgContext.scaleBy(x: 1, y: -1)
        let context = NSGraphicsContext(cgContext: cgContext, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        defer { NSGraphicsContext.restoreGraphicsState() }
        gutter.drawHashMarksAndLabels(in: bounds)

        let background = luma(bitmap, 0, 0)
        let produced = try #require(secondLabelMask(in: bitmap, background: background), "two labels must be drawn")
        // Polarity was established by mutation: with the production `textMatrix` line removed the same render scores
        // about -7 (an inverted glyph); with it, clearly positive.
        let producedScore = bottomHeaviness(produced)
        #expect(producedScore > 2, "the production-drawn '2' must be upright, i.e. bottom-heavy (\(producedScore))")
    }
}
