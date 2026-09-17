@testable import DiagramsGraphviz
import Foundation
@testable import GraphvizRendering
import Testing

/// Real, end-to-end pipeline tests — genuine WebKit, genuine bundled
/// viz-js/Graphviz, no fakes.
@Suite("GraphvizWebRenderer")
struct GraphvizWebRendererTests {
    private static let context = GraphvizRenderContext(
        foregroundRed: 0, foregroundGreen: 0, foregroundBlue: 0,
        backgroundRed: 1, backgroundGreen: 1, backgroundBlue: 1
    )

    private static func fence(_ source: String) -> GraphvizFence {
        GraphvizFence(source: source, sourceRange: 0 ..< source.count)
    }

    @Test func renderProducesRealSVGForValidSource() async throws {
        let renderer = GraphvizWebRenderer()
        let diagram = try await renderer.render(Self.fence("digraph { a -> b; b -> c; }"), context: Self.context)
        #expect(diagram.svg.contains("<svg"))
        #expect(diagram.naturalWidth > 0)
        #expect(diagram.naturalHeight > 0)
        // Confirmed by a real Slice 0 spike: Graphviz's native output has
        // no <foreignObject>, which is exactly why RenderedGraphvizDiagram
        // carries no pngData field — this assertion keeps that assumption
        // honest.
        #expect(!diagram.svg.contains("foreignObject"))
        await renderer.shutdown()
    }

    @Test func renderThrowsInvalidSyntaxForMalformedSource() async throws {
        let renderer = GraphvizWebRenderer()
        await #expect(throws: GraphvizRenderError.self) {
            _ = try await renderer.render(Self.fence("digraph { a -> "), context: Self.context)
        }
        await renderer.shutdown()
    }

    @Test func renderRecoversAfterAPriorFailureOnTheSamePooledPage() async throws {
        let renderer = GraphvizWebRenderer(poolSize: 1)
        await #expect(throws: GraphvizRenderError.self) {
            _ = try await renderer.render(Self.fence("digraph { a -> "), context: Self.context)
        }
        let diagram = try await renderer.render(Self.fence("digraph { a -> b; }"), context: Self.context)
        #expect(diagram.svg.contains("<svg"))
        await renderer.shutdown()
    }

    @Test func renderTimesOutWhenTheBudgetIsSetBelowRealRenderTime() async throws {
        let renderer = GraphvizWebRenderer(timeout: .milliseconds(1))
        await #expect(throws: GraphvizRenderError.timedOut) {
            _ = try await renderer.render(Self.fence("digraph { a -> b; }"), context: Self.context)
        }
        await renderer.shutdown()
    }

    @Test func renderRejectsOutputAboveTheConfiguredSizeCeiling() async throws {
        let renderer = GraphvizWebRenderer(maxOutputBytes: 10)
        await #expect(throws: GraphvizRenderError.self) {
            _ = try await renderer.render(Self.fence("digraph { a -> b; }"), context: Self.context)
        }
        await renderer.shutdown()
    }

    @Test func concurrentRendersAllCompleteAcrossABoundedPool() async throws {
        let renderer = GraphvizWebRenderer(poolSize: 2)
        try await withThrowingTaskGroup(of: RenderedGraphvizDiagram.self) { group in
            for index in 0 ..< 6 {
                group.addTask {
                    try await renderer.render(
                        Self.fence("digraph { a\(index) -> b\(index); }"), context: Self.context
                    )
                }
            }
            var count = 0
            for try await diagram in group {
                #expect(diagram.svg.contains("<svg"))
                count += 1
            }
            #expect(count == 6)
        }
        await renderer.shutdown()
    }

    @Test func rendererReinitializesLazilyAfterShutdown() async throws {
        let renderer = GraphvizWebRenderer(poolSize: 1)
        _ = try await renderer.render(Self.fence("digraph { a -> b; }"), context: Self.context)
        await renderer.shutdown()
        let diagram = try await renderer.render(Self.fence("digraph { a -> b; }"), context: Self.context)
        #expect(diagram.svg.contains("<svg"))
        await renderer.shutdown()
    }
}
