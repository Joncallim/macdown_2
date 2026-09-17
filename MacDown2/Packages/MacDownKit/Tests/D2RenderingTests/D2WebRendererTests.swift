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
}
