import Foundation

/// The injected-renderer seam, mirroring `MermaidDiagramRendering`.
public protocol D2DiagramRendering: Sendable {
    func render(_ fence: D2Fence, context: D2RenderContext) async throws -> RenderedD2Diagram
}
