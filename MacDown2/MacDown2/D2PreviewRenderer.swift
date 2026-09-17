import Contributions
import DiagramsD2
import Foundation

/// Preview-facing name for the one process-lifetime, shared renderer/cache
/// instance also used by Export (`ContributionRegistry.sharedD2Renderer`,
/// `D2ExportRegistry.swift`). Mirrors `MermaidPreviewRenderer.swift`'s
/// exact shape.
enum D2PreviewRenderer {
    static var shared: any D2DiagramRendering {
        ContributionRegistry.sharedD2Renderer
    }
}
