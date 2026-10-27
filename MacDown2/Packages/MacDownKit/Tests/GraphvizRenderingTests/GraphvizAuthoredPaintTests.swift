@testable import DiagramsGraphviz
import Foundation
@testable import GraphvizRendering
import Testing

@Suite("Graphviz authored paints")
struct GraphvizAuthoredPaintTests {
    private func fence(_ source: String) -> GraphvizFence {
        GraphvizFence(source: source, sourceRange: 0 ..< source.count)
    }

    private func nodeBody(title: String, in svg: String) throws -> String {
        let escapedTitle = NSRegularExpression.escapedPattern(for: title)
        let pattern = "(?s)<g id=\"[^\"]+\" class=\"node\">.*?<title>\(escapedTitle)</title>.*?</g>"
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(svg.startIndex..., in: svg)
        let match = try #require(regex.firstMatch(in: svg, range: range))
        let matchRange = try #require(Range(match.range, in: svg))
        return String(svg[matchRange])
    }

    @Test func explicitBlackAndGradientNodeStylesRemainAuthoritative() async throws {
        let renderer = GraphvizWebRenderer()
        let black = try await renderer.render(
            fence("digraph { a [style=filled, color=black, fontcolor=white]; }"),
            context: GraphvizRenderContext(
                foregroundRed: 1, foregroundGreen: 1, foregroundBlue: 1,
                backgroundRed: 0, backgroundGreen: 0, backgroundBlue: 0
            )
        )
        #expect(try nodeBody(title: "a", in: black.svg).contains("fill=\"black\""))

        let gradient = try await renderer.render(
            fence("digraph { a [style=filled, fillcolor=\"red:blue\"]; }"),
            context: .neutralLight
        )
        #expect(gradient.svg.localizedCaseInsensitiveContains("linearGradient"))
        #expect(try nodeBody(title: "a", in: gradient.svg).localizedCaseInsensitiveContains("fill=\"url("))
        await renderer.shutdown()
    }
}
