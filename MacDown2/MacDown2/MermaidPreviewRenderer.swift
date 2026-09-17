import Contributions
import Diagrams
import Foundation

/// Preview-facing name for the one process-lifetime, shared renderer/cache
/// instance also used by Export (`ContributionRegistry.sharedMermaidRenderer`,
/// `MermaidExportRegistry.swift`) — the same instance, not a second one, so
/// a diagram already rendered for one destination is not re-rendered for
/// the other (epic-20-implementation.md §5). This alias exists so
/// Preview-side call sites (`DocumentEditorSplitView.swift`) reference a
/// name from their own domain rather than reaching into
/// `ContributionRegistry`, which is an Export/`Contributing`-domain type
/// Preview otherwise has no reason to import.
enum MermaidPreviewRenderer {
    static var shared: any MermaidDiagramRendering {
        ContributionRegistry.sharedMermaidRenderer
    }
}
