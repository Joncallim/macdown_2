@testable import DiagramRendering
import Foundation
import Testing
import WebKit

extension RealSVGNamespaceTests {
    @MainActor func png(for svg: String, on canvas: MermaidHarnessPage) async throws -> Data {
        // Export embeds this sanitized fragment in HTML. Let the browser
        // restore SVG attribute casing (for example viewbox -> viewBox) before
        // handing it to the canvas probe, which deliberately parses strict XML.
        let view = WKWebView(frame: .zero)
        let normalized = try #require(try await view.callAsyncJavaScript(
            """
            const root = new DOMParser().parseFromString(svg, 'text/html').querySelector('svg');
            return new XMLSerializer().serializeToString(root);
            """,
            arguments: ["svg": svg], in: nil, contentWorld: .page
        ) as? String)
        let result = try await canvas.inspectSVGCanvasForTesting(normalized)
        let base64 = try #require(result["png"] as? String)
        return try #require(Data(base64Encoded: base64))
    }
}
