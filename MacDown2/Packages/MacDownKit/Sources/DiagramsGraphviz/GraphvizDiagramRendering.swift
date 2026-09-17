import Foundation

/// The injected-renderer seam, mirroring `MermaidDiagramRendering`.
public protocol GraphvizDiagramRendering: Sendable {
    func render(_ fence: GraphvizFence, context: GraphvizRenderContext) async throws -> RenderedGraphvizDiagram
}
