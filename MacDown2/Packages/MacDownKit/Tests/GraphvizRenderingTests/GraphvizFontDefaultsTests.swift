@testable import DiagramsGraphviz
import Foundation
@testable import GraphvizRendering
import Testing

@Suite("Graphviz native font defaults")
struct GraphvizFontDefaultsTests {
    private func fence(_ source: String) -> GraphvizFence {
        GraphvizFence(source: source, sourceRange: 0 ..< source.count)
    }

    private func fontFamily(forLabel label: String, in svg: String) throws -> String {
        let escapedLabel = NSRegularExpression.escapedPattern(for: label)
        let pattern = #"<text[^>]*font-family=\"([^\"]+)\"[^>]*>"# + escapedLabel + #"</text>"#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(svg.startIndex..., in: svg)
        let match = try #require(regex.firstMatch(in: svg, range: range))
        return try #require(Range(match.range(at: 1), in: svg).map { String(svg[$0]) })
    }

    @Test func generatedLabelsUseNativeSansDefaultsAcrossGraphScopesAndThemes() async throws {
        let renderer = GraphvizWebRenderer(poolSize: 1)
        let source = """
        digraph {
            label = "graph label";
            subgraph cluster_group { label = "cluster label"; alpha; }
            alpha -> beta [label = "edge label"];
        }
        """
        let light = try await renderer.render(fence(source), context: .neutralLight).svg
        let dark = try await renderer.render(
            fence(source),
            context: GraphvizRenderContext(
                foregroundRed: 0.9, foregroundGreen: 0.9, foregroundBlue: 0.9,
                backgroundRed: 0.1, backgroundGreen: 0.1, backgroundBlue: 0.1
            )
        ).svg
        let lightAgain = try await renderer.render(fence(source), context: .neutralLight).svg
        for svg in [light, dark, lightAgain] {
            for label in ["graph label", "cluster label", "alpha", "edge label"] {
                #expect(try fontFamily(forLabel: label, in: svg).hasPrefix("Helvetica"))
            }
        }
        await renderer.shutdown()
    }

    @Test func authoredFontsOverrideGeneratedSansDefaults() async throws {
        let renderer = GraphvizWebRenderer()
        let source = """
        digraph {
            label = "graph label";
            fontname = "Times-Roman";
            subgraph cluster_group { label = "cluster label"; fontname = "Courier"; alpha [fontname = "Palatino"]; }
            alpha -> beta [label = "edge label", fontname = "Arial"];
        }
        """
        let svg = try await renderer.render(fence(source), context: .neutralLight).svg
        #expect(try fontFamily(forLabel: "graph label", in: svg).hasPrefix("Times"))
        #expect(try fontFamily(forLabel: "cluster label", in: svg).hasPrefix("Courier"))
        #expect(try fontFamily(forLabel: "alpha", in: svg).hasPrefix("Palatino"))
        #expect(try fontFamily(forLabel: "edge label", in: svg).hasPrefix("Arial"))
        await renderer.shutdown()
    }
}
