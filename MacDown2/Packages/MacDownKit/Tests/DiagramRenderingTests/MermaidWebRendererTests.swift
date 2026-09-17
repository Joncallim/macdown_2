@testable import DiagramRendering
import Diagrams
import Foundation
import Testing

@Suite("MermaidWebRenderer")
struct MermaidWebRendererTests {
    private static let context = MermaidRenderContext(
        foregroundRed: 0, foregroundGreen: 0, foregroundBlue: 0,
        backgroundRed: 1, backgroundGreen: 1, backgroundBlue: 1
    )

    private static func fence(_ source: String) -> MermaidFence {
        MermaidFence(source: source, sourceRange: 0 ..< source.count)
    }

    /// A real, end-to-end pipeline test — genuine WebKit, genuine bundled
    /// Mermaid, no fakes — matching this codebase's precedent
    /// (`MathImageRendererTests`' real `ImageRenderer`,
    /// `DocumentFileMonitorLiveWatcherTests`' real kqueue watcher) of
    /// preferring real dependencies over mocks wherever the real thing can
    /// run under `swift test` (confirmed feasible by this epic's own Slice
    /// 0 spike).
    @Test func renderProducesRealSVGForValidSource() async throws {
        let renderer = MermaidWebRenderer()
        let diagram = try await renderer.render(Self.fence("graph TD; A-->B;"), context: Self.context)
        #expect(diagram.svg.contains("<svg"))
        #expect(diagram.naturalWidth > 0)
        #expect(diagram.naturalHeight > 0)
        await renderer.shutdown()
    }

    /// A real, WebKit-rendered raster snapshot of the diagram, used for
    /// native Preview display (§7.2's `MermaidDiagramBlockView`) because a
    /// real spike proved AppKit's own SVG decoder cannot reliably display
    /// Mermaid's actual output (`RenderedMermaidDiagram`'s own doc comment;
    /// `render.js`'s `png` field comment has the full finding). The PNG
    /// magic-byte check confirms this is genuine decodable image data, not
    /// merely a non-empty byte blob.
    @Test func renderProducesAValidPNGSnapshotAlongsideTheSVG() async throws {
        let renderer = MermaidWebRenderer()
        let diagram = try await renderer.render(Self.fence("graph TD; A-->B;"), context: Self.context)
        let pngData = try #require(diagram.pngData)
        let pngMagicBytes: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        #expect(Array(pngData.prefix(8)) == pngMagicBytes)
        #expect(pngData.count > 100)
        await renderer.shutdown()
    }

    @Test func renderThrowsInvalidSyntaxForMalformedSource() async throws {
        let renderer = MermaidWebRenderer()
        await #expect(throws: MermaidRenderError.self) {
            _ = try await renderer.render(Self.fence("graph TD; A-->"), context: Self.context)
        }
        await renderer.shutdown()
    }

    @Test func renderRecoversAfterAPriorFailureOnTheSamePooledPage() async throws {
        let renderer = MermaidWebRenderer(poolSize: 1)
        await #expect(throws: MermaidRenderError.self) {
            _ = try await renderer.render(Self.fence("not a diagram at all {{{"), context: Self.context)
        }
        // The same (only) pooled page must still work for the next request —
        // a failed render must not leave the page in a poisoned state.
        let diagram = try await renderer.render(Self.fence("graph TD; A-->B;"), context: Self.context)
        #expect(diagram.svg.contains("<svg"))
        await renderer.shutdown()
    }

    @Test func renderTimesOutWhenTheBudgetIsSetBelowRealRenderTime() async throws {
        let renderer = MermaidWebRenderer(timeout: .milliseconds(1))
        await #expect(throws: MermaidRenderError.timedOut) {
            _ = try await renderer.render(Self.fence("graph TD; A-->B;"), context: Self.context)
        }
        await renderer.shutdown()
    }

    @Test func renderRejectsOutputAboveTheConfiguredSizeCeiling() async throws {
        let renderer = MermaidWebRenderer(maxOutputBytes: 10)
        await #expect(throws: MermaidRenderError.self) {
            _ = try await renderer.render(Self.fence("graph TD; A-->B;"), context: Self.context)
        }
        await renderer.shutdown()
    }

    @Test func concurrentRendersAllCompleteAcrossABoundedPool() async throws {
        let renderer = MermaidWebRenderer(poolSize: 2)
        try await withThrowingTaskGroup(of: RenderedMermaidDiagram.self) { group in
            for index in 0 ..< 6 {
                group.addTask {
                    try await renderer.render(Self.fence("graph TD; A-->B\(index);"), context: Self.context)
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
        let renderer = MermaidWebRenderer(poolSize: 1)
        _ = try await renderer.render(Self.fence("graph TD; A-->B;"), context: Self.context)
        await renderer.shutdown()
        // A fresh page must be created on demand, not left permanently torn down.
        let diagram = try await renderer.render(Self.fence("graph TD; A-->B;"), context: Self.context)
        #expect(diagram.svg.contains("<svg"))
        await renderer.shutdown()
    }

    /// Directly verifies the §10 trust-boundary assumption this epic relies
    /// on, rather than merely asserting it in prose: Mermaid's
    /// `securityLevel: 'strict'` (set in the bundled harness's `render.js`)
    /// must suppress `click` interaction directives, so a diagram attempting
    /// one never produces a live, callable interaction in the output SVG.
    @Test func strictSecurityLevelSuppressesClickDirectives() async throws {
        let renderer = MermaidWebRenderer()
        let source = """
        graph TD
            A-->B
            click A "javascript:alert(1)"
        """
        let diagram = try await renderer.render(Self.fence(source), context: Self.context)
        #expect(!diagram.svg.contains("javascript:alert"))
        await renderer.shutdown()
    }

    /// Adversarial corpus (epic-20-implementation.md §15): a genuinely
    /// larger, more realistic diagram — not just a two-node smoke test —
    /// to catch problems that only appear with real layout complexity
    /// (long render time, degenerate output, a raster snapshot too small
    /// to be useful). 12 nodes, a cluster, and multiple edge label styles.
    @Test func renderHandlesAModeratelyComplexDiagramWithinTheDefaultTimeout() async throws {
        let renderer = MermaidWebRenderer()
        let source = """
        graph TD
            Start[Start] --> Auth{Authenticated?}
            Auth -->|No| Login[Show Login]
            Login --> Auth
            Auth -->|Yes| Dashboard[Dashboard]
            subgraph Processing
                Dashboard --> Fetch[Fetch Data]
                Fetch --> Validate{Valid?}
                Validate -->|No| Error[Show Error]
                Validate -->|Yes| Transform[Transform Data]
                Transform --> Cache[(Cache)]
            end
            Cache --> Render[Render View]
            Error --> Dashboard
            Render --> End([Done])
        """
        let diagram = try await renderer.render(Self.fence(source), context: Self.context)
        #expect(diagram.svg.contains("<svg"))
        #expect(diagram.naturalWidth > 0)
        #expect(diagram.naturalHeight > 0)
        let pngData = try #require(diagram.pngData)
        #expect(pngData.count > 1000)
        await renderer.shutdown()
    }

    /// Adversarial corpus: whitespace-only source is not valid Mermaid
    /// syntax and must fail the same safe, diagnosable way as any other
    /// malformed input — never hang, never crash, never produce an empty
    /// but "successful" diagram.
    @Test func renderFailsSafelyOnWhitespaceOnlySource() async throws {
        let renderer = MermaidWebRenderer()
        await #expect(throws: MermaidRenderError.self) {
            _ = try await renderer.render(Self.fence("   \n\n   "), context: Self.context)
        }
        await renderer.shutdown()
    }
}
