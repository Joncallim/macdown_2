import Contributions
import DiagramsGraphviz
import Foundation

/// Preview-facing name for the one process-lifetime, shared renderer/cache
/// instance also used by Export (`ContributionRegistry.sharedGraphvizRenderer`,
/// `GraphvizExportRegistry.swift`). Mirrors `MermaidPreviewRenderer.swift`'s
/// exact shape.
enum GraphvizPreviewRenderer {
    static var shared: any GraphvizDiagramRendering {
        ContributionRegistry.sharedGraphvizRenderer
    }
}
