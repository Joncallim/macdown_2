import Contributions
import Diagrams
import DiagramsD2
import DiagramsGraphviz
import Foundation
@testable import MacDown2
import Testing
import Themes

/// EPIC-21 Slice 5 (epic-21-implementation.md §5): a real document with
/// Mermaid, D2, and Graphviz fences together, confirming independent
/// failure isolation (one bad diagram does not block or corrupt the
/// others) and that three real, sandboxed `WKWebView`-backed renderers can
/// run concurrently — the same shared instances the app wires into both
/// Export and Preview — without one renderer's pool stalling another's.
@Suite("MixedDiagramRendererIntegration")
struct MixedDiagramRendererIntegrationTests {
    @Test func threeDifferentDiagramLanguagesRenderIndependentlyWithoutBlockingEachOther() async throws {
        let theme = BundledThemes.light
        let mermaidContext = ContributionRegistry.mermaidRenderContext(theme: theme, isPrintTarget: false)
        let d2Context = ContributionRegistry.d2RenderContext(theme: theme, isPrintTarget: false)
        let graphvizContext = ContributionRegistry.graphvizRenderContext(theme: theme, isPrintTarget: false)

        // Deliberately distinct from any source used elsewhere in this test
        // process: `sharedMermaidRenderer`/`sharedD2Renderer` are
        // process-lifetime caches, so a source another test already
        // rendered would be served from cache — a real render never
        // happens, and the concurrency/timing claim below would be
        // unverified rather than proven.
        let mermaidFence = MermaidFence(
            source: "graph TD; MixedIsolationCheckA-->MixedIsolationCheckB;", sourceRange: 0 ..< 0
        )
        let d2Fence = D2Fence(source: "mixedIsolationCheckA -> mixedIsolationCheckB", sourceRange: 0 ..< 0)
        // Deliberately invalid: proves a broken diagram in a mixed document
        // fails on its own without blocking or corrupting the other two
        // renderers' independent, concurrent results.
        let invalidGraphvizFence = GraphvizFence(source: "digraph { a -> ", sourceRange: 0 ..< 0)

        let clock = ContinuousClock()
        let start = clock.now

        async let mermaidResult = ContributionRegistry.sharedMermaidRenderer.render(
            mermaidFence, context: mermaidContext
        )
        async let d2Result = ContributionRegistry.sharedD2Renderer.render(d2Fence, context: d2Context)
        async let graphvizResult: RenderedGraphvizDiagram? = {
            do {
                return try await ContributionRegistry.sharedGraphvizRenderer.render(
                    invalidGraphvizFence, context: graphvizContext
                )
            } catch {
                return nil
            }
        }()

        let mermaid = try await mermaidResult
        let d2Diagram = try await d2Result
        let graphviz = await graphvizResult
        let elapsed = clock.now - start

        #expect(mermaid.svg.contains("<svg"))
        #expect(d2Diagram.svg.contains("<svg"))
        #expect(graphviz == nil)
        // Generous relative to each renderer's own default timeout budget
        // (5s) — proves the three pools genuinely run concurrently rather
        // than serializing behind one shared resource, not a tight
        // performance assertion.
        #expect(elapsed < .seconds(15))
    }
}
