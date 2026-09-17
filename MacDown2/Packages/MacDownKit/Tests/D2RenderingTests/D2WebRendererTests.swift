@testable import D2Rendering
import DiagramsD2
import Foundation
import Testing

/// Real, end-to-end pipeline tests — genuine WebKit, genuine bundled D2,
/// no fakes — matching this codebase's precedent for preferring real
/// dependencies over mocks wherever the real thing can run under
/// `swift test` (epic-20-implementation.md's own Slice 0 spike;
/// `MermaidWebRendererTests`).
@Suite("D2WebRenderer")
struct D2WebRendererTests {
    private static let context = D2RenderContext(
        foregroundRed: 0, foregroundGreen: 0, foregroundBlue: 0,
        backgroundRed: 1, backgroundGreen: 1, backgroundBlue: 1
    )

    private static func fence(_ source: String) -> D2Fence {
        D2Fence(source: source, sourceRange: 0 ..< source.count)
    }

    @Test func renderProducesRealSVGForValidSource() async throws {
        let renderer = D2WebRenderer()
        let diagram = try await renderer.render(Self.fence("a -> b -> c"), context: Self.context)
        #expect(diagram.svg.contains("<svg"))
        #expect(diagram.naturalWidth > 0)
        #expect(diagram.naturalHeight > 0)
        // Confirmed by a real Slice 0 spike: D2's native output has no
        // <foreignObject>, which is exactly why RenderedD2Diagram carries
        // no pngData field — this assertion keeps that assumption honest.
        #expect(!diagram.svg.contains("foreignObject"))
        await renderer.shutdown()
    }

    @Test func renderThrowsInvalidSyntaxForMalformedSource() async throws {
        let renderer = D2WebRenderer()
        await #expect(throws: D2RenderError.self) {
            _ = try await renderer.render(Self.fence("{{{ not valid d2 ]["), context: Self.context)
        }
        await renderer.shutdown()
    }

    @Test func renderRecoversAfterAPriorFailureOnTheSamePooledPage() async throws {
        let renderer = D2WebRenderer(poolSize: 1)
        await #expect(throws: D2RenderError.self) {
            _ = try await renderer.render(Self.fence("{{{ not valid d2 ]["), context: Self.context)
        }
        let diagram = try await renderer.render(Self.fence("a -> b"), context: Self.context)
        #expect(diagram.svg.contains("<svg"))
        await renderer.shutdown()
    }

    @Test func renderTimesOutWhenTheBudgetIsSetBelowRealRenderTime() async throws {
        let renderer = D2WebRenderer(timeout: .milliseconds(1))
        await #expect(throws: D2RenderError.timedOut) {
            _ = try await renderer.render(Self.fence("a -> b"), context: Self.context)
        }
        await renderer.shutdown()
    }

    @Test func renderRejectsOutputAboveTheConfiguredSizeCeiling() async throws {
        let renderer = D2WebRenderer(maxOutputBytes: 10)
        await #expect(throws: D2RenderError.self) {
            _ = try await renderer.render(Self.fence("a -> b"), context: Self.context)
        }
        await renderer.shutdown()
    }

    @Test func concurrentRendersAllCompleteAcrossABoundedPool() async throws {
        let renderer = D2WebRenderer(poolSize: 2)
        try await withThrowingTaskGroup(of: RenderedD2Diagram.self) { group in
            for index in 0 ..< 6 {
                group.addTask {
                    try await renderer.render(Self.fence("a\(index) -> b\(index)"), context: Self.context)
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
        let renderer = D2WebRenderer(poolSize: 1)
        _ = try await renderer.render(Self.fence("a -> b"), context: Self.context)
        await renderer.shutdown()
        let diagram = try await renderer.render(Self.fence("a -> b"), context: Self.context)
        #expect(diagram.svg.contains("<svg"))
        await renderer.shutdown()
    }

    /// Adversarial corpus (epic-21-implementation.md Slice 5, mirroring
    /// epic-20-implementation.md §15): a genuinely larger, more realistic
    /// diagram — not just a two-node smoke test — to catch problems that
    /// only appear with real layout complexity (long render time,
    /// degenerate output). Containers, multiple shapes, and styled
    /// connections.
    @Test func renderHandlesAModeratelyComplexDiagramWithinTheDefaultTimeout() async throws {
        let renderer = D2WebRenderer()
        let source = """
        classes: {
          service: { style.fill: "#e3f2fd" }
        }
        client: Client
        gateway: API Gateway
        auth: Auth Service { class: service }
        orders: Orders Service { class: service }
        db: Database { shape: cylinder }
        client -> gateway: request
        gateway -> auth: verify token
        gateway -> orders: forward
        orders -> db: read/write
        auth -> db: lookup user
        gateway -> client: response {
          style.stroke-dash: 3
        }
        """
        let diagram = try await renderer.render(Self.fence(source), context: Self.context)
        #expect(diagram.svg.contains("<svg"))
        #expect(diagram.naturalWidth > 0)
        #expect(diagram.naturalHeight > 0)
        await renderer.shutdown()
    }

    /// Adversarial corpus: whitespace-only source must fail (or otherwise
    /// resolve) the same safe, diagnosable way every time — never hang,
    /// never crash. D2 tolerates an empty document as a real, deliberate
    /// language feature (an empty diagram is valid D2), so this asserts
    /// the safe-completion contract rather than assuming an error, unlike
    /// Mermaid/Graphviz which both require a real keyword to parse.
    @Test func renderCompletesSafelyOnWhitespaceOnlySource() async throws {
        let renderer = D2WebRenderer()
        let diagram = try await renderer.render(Self.fence("   \n\n   "), context: Self.context)
        #expect(diagram.svg.contains("<svg"))
        await renderer.shutdown()
    }
}
