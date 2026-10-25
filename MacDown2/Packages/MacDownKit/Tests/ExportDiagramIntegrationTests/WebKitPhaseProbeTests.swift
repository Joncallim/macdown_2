import D2Rendering
import DiagramRendering
import Diagrams
import DiagramsD2
import DiagramsGraphviz
import GraphvizRendering
import Testing

@Suite("WebKit phase probe")
struct WebKitPhaseProbeTests {
    @Test @MainActor func repeatedCrossEnginePageConstructionAndEvaluation() async throws {
        for _ in 0 ..< 30 {
            let d2Renderer = D2WebRenderer()
            do {
                _ = try await d2Renderer.render(
                    D2Fence(source: "a -> b", sourceRange: 0 ..< 6),
                    context: D2RenderContext(
                        foregroundRed: 0, foregroundGreen: 0, foregroundBlue: 0,
                        backgroundRed: 1, backgroundGreen: 1, backgroundBlue: 1
                    )
                )
            } catch {
                await d2Renderer.shutdown()
                throw error
            }
            await d2Renderer.shutdown()

            let graphviz = GraphvizWebRenderer()
            do {
                _ = try await graphviz.render(
                    GraphvizFence(source: "digraph { a -> b; }", sourceRange: 0 ..< 19),
                    context: GraphvizRenderContext(
                        foregroundRed: 0, foregroundGreen: 0, foregroundBlue: 0,
                        backgroundRed: 1, backgroundGreen: 1, backgroundBlue: 1
                    )
                )
            } catch {
                await graphviz.shutdown()
                throw error
            }
            await graphviz.shutdown()

            let mermaid = MermaidWebRenderer()
            do {
                _ = try await mermaid.render(
                    MermaidFence(source: "graph TD; A-->B;", sourceRange: 0 ..< 16),
                    context: MermaidRenderContext(
                        foregroundRed: 0, foregroundGreen: 0, foregroundBlue: 0,
                        backgroundRed: 1, backgroundGreen: 1, backgroundBlue: 1
                    )
                )
            } catch {
                await mermaid.shutdown()
                throw error
            }
            await mermaid.shutdown()
        }
    }
}
