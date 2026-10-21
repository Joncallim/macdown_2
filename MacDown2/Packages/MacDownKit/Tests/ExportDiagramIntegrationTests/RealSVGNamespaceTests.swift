import D2Rendering
@testable import DiagramRendering
import Diagrams
import DiagramsD2
import DiagramsGraphviz
@testable import ExportService
import Foundation
import GraphvizRendering
import Testing

@Suite("Real diagram SVG namespace compatibility")
struct RealSVGNamespaceTests {
    @Test @MainActor func representativeRendererOutputsRemainAdmissible() async throws {
        let graphviz = GraphvizWebRenderer()
        let dot = try await graphviz.render(
            GraphvizFence(source: "digraph { a -> b; b -> c; }", sourceRange: 0 ..< 28),
            context: GraphvizRenderContext(
                foregroundRed: 0, foregroundGreen: 0, foregroundBlue: 0,
                backgroundRed: 1, backgroundGreen: 1, backgroundBlue: 1
            )
        )
        await graphviz.shutdown()

        let d2Renderer = D2WebRenderer()
        let d2Diagram = try await d2Renderer.render(
            D2Fence(source: "a -> b -> c", sourceRange: 0 ..< 11),
            context: D2RenderContext(
                foregroundRed: 0, foregroundGreen: 0, foregroundBlue: 0,
                backgroundRed: 1, backgroundGreen: 1, backgroundBlue: 1
            )
        )
        await d2Renderer.shutdown()

        let mermaidRenderer = MermaidWebRenderer()
        let mermaid = try await mermaidRenderer.render(
            MermaidFence(source: "graph TD; A-->B;", sourceRange: 0 ..< 16),
            context: MermaidRenderContext(
                foregroundRed: 0, foregroundGreen: 0, foregroundBlue: 0,
                backgroundRed: 1, backgroundGreen: 1, backgroundBlue: 1
            )
        )
        await mermaidRenderer.shutdown()

        let canvas = try await MermaidHarnessPage.make()
        defer { canvas.teardown() }

        for (name, svg) in [("Graphviz", dot.svg), ("D2", d2Diagram.svg), ("Mermaid", mermaid.svg)] {
            try await check(name: name, svg: svg, on: canvas)
        }
    }

    @MainActor private func check(name: String, svg: String, on canvas: MermaidHarnessPage) async throws {
        let sanitized = DerivedHTMLSanitizer.sanitized(svg)
        let rewritten = try #require(SVGIDNamespace.rewrite(sanitized, occurrence: 0))
        if let directory = ProcessInfo.processInfo.environment["MOSTLYTEXT_117_FIXTURE_DIR"] {
            let folder = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try svg.write(to: folder.appending(path: "\(name).svg"), atomically: true, encoding: .utf8)
            try sanitized.write(to: folder.appending(path: "\(name)-sanitized.svg"),
                                atomically: true, encoding: .utf8)
        }
        print("#117 real \(name): source=\(svg.utf8.count)B sanitized=\(sanitized.utf8.count)B "
            + "namespaced=\(rewritten.utf8.count)B")
        let originalIDs = try ids(in: sanitized)
        let rewrittenIDs = try ids(in: rewritten)
        #expect(!originalIDs.isEmpty)
        #expect(rewrittenIDs == originalIDs.map { "mt117-svg-0-0-" + $0 })
        for id in originalIDs {
            if sanitized.contains("url(#\(id))") {
                #expect(rewritten.contains("url(#mt117-svg-0-0-\(id))"))
            }
            if sanitized.contains("href=\"#\(id)\"") {
                #expect(rewritten.contains("href=\"#mt117-svg-0-0-\(id)\""))
            }
        }
        let before = try await png(for: sanitized, on: canvas)
        let after = try await png(for: rewritten, on: canvas)
        #expect(before == after, "\(name) canvas pixels changed after ID namespacing")
    }

    private func ids(in svg: String) throws -> [String] {
        let expression = try NSRegularExpression(pattern: #"(?<![A-Za-z0-9_-])id="([^"]+)""#)
        let source = svg as NSString
        return expression.matches(in: svg, range: NSRange(location: 0, length: source.length))
            .map { source.substring(with: $0.range(at: 1)) }
    }

    @MainActor private func png(for svg: String, on canvas: MermaidHarnessPage) async throws -> Data {
        let result = try await canvas.inspectSVGCanvasForTesting(svg)
        let base64 = try #require(result["png"] as? String)
        return try #require(Data(base64Encoded: base64))
    }
}
