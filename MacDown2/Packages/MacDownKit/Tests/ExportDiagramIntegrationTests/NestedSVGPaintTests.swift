import AppKit
@testable import ExportService
import Foundation
import Testing
import WebKit

extension AssembledSVGResourceTests {
    @Test func authoredOuterSVGCanPassAnOutsidePaintIntoAMarkedInnerSVG() async throws {
        let inner = #"<svg id="inner" width="48" height="48">"#
            + #"<rect id="shape" width="48" height="48"/></svg>"#
        let marked = try #require(SVGIDNamespace.rewriteMarked(inner, occurrence: 0))
        let outer = #"<svg width="80" height="80" fill="url(#outside)"><defs>"#
            + #"<linearGradient id="outside"><stop stop-color="blue"/></linearGradient>"#
            + "</defs>\(marked.html)</svg>"
        let document = BuiltInExportTemplate.document(
            title: "Inherited outside paint", styleElement: "<style></style>", body: outer
        )
        // Before the nested-root guard, the outer resource edge is treated
        // as unrelated even though fill inherits into this inner rectangle.
        #expect(SVGAssemblyOwnership.inspect(markedDocument: document, fragment: marked) == nil)

        let view = WKWebView(frame: .init(x: 0, y: 0, width: 80, height: 80))
        view.loadHTMLString(document, baseURL: nil)
        try await waitForLoad(in: view)
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        var expectedDOMLoaded = false
        while ContinuousClock.now < deadline {
            expectedDOMLoaded = await (try? view.evaluateJavaScript(
                "document.title === 'Inherited outside paint' && document.querySelectorAll('svg svg rect').length === 1"
            ) as? Bool) == true
            if expectedDOMLoaded {
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(expectedDOMLoaded)
        let fill = try #require(try await view.evaluateJavaScript(
            "getComputedStyle(document.querySelector('svg svg rect')).fill"
        ) as? String)
        #expect(fill.contains("outside"))
        let image = try await view.takeSnapshot(configuration: nil)
        let tiff = try #require(image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiff))
        var bluePixels = 0
        for pixelY in stride(from: 0, to: bitmap.pixelsHigh, by: 4) {
            for pixelX in stride(from: 0, to: bitmap.pixelsWide, by: 4) {
                guard let color = bitmap.colorAt(x: pixelX, y: pixelY)?.usingColorSpace(.deviceRGB)
                else { continue }
                if color.blueComponent > color.redComponent + 0.2,
                   color.blueComponent > color.greenComponent + 0.2 {
                    bluePixels += 1
                }
            }
        }
        #expect(bluePixels > 10)
    }
}
