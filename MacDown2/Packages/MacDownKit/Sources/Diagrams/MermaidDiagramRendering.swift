import Foundation

/// The injected-renderer seam (epic-20-implementation.md §6), parallel to
/// `MathImageRendering`. A protocol rather than a closure typealias because,
/// unlike Math's single free function, Mermaid's real implementation
/// (`MermaidWebRenderer`, `DiagramRendering` target) is stateful — it owns a
/// pool of long-lived offscreen web views — and benefits from an explicit
/// type identity for tests and document-close cleanup.
public protocol MermaidDiagramRendering: Sendable {
    func render(_ fence: MermaidFence, context: MermaidRenderContext) async throws -> RenderedMermaidDiagram
}
