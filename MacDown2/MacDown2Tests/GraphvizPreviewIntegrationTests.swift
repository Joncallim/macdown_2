import Contributions
import DiagramsGraphviz
import Foundation
@testable import MacDown2
import MarkdownEngine
import Preview
import Testing
import Themes

/// End to end, from real parsing through to a real rendered diagram,
/// mirroring `MermaidPreviewIntegrationTests`'s exact approach
/// (epic-21-implementation.md §5 Slice 4).
@Suite("GraphvizPreviewIntegration")
struct GraphvizPreviewIntegrationTests {
    @Test func aRealGraphvizFenceSlicesIntoAPreviewBlockWithTheCorrectLanguageTag() async throws {
        let text = "# Title\n\n```dot\ndigraph { a -> b }\n```\n"
        let document = try await ParseEngine().parse(text, revision: 0)
        let blocks = PreviewBlock.blocks(from: document, text: text)

        let graphvizBlock = try #require(blocks.first { block in
            guard case let .codeBlock(language) = block.kind else { return false }
            return language?.lowercased() == "dot"
        })
        #expect(!graphvizBlock.isOversize)
    }

    @Test func stripDelimitersOnARealSlicedPreviewBlockRecoversExactlyTheAuthoredDiagramSource() async throws {
        let text = "```dot\ndigraph { a -> b }\n```\n"
        let document = try await ParseEngine().parse(text, revision: 0)
        let blocks = PreviewBlock.blocks(from: document, text: text)
        let graphvizBlock = try #require(blocks.first)

        let stripped = GraphvizFenceContent.stripDelimiters(from: graphvizBlock.source)
        #expect(stripped == "digraph { a -> b }")
    }

    /// Uses the SAME shared instance the app's real Preview wiring
    /// (`DocumentEditorSplitView+D2Graphviz.swift`) and Export
    /// (`GraphvizExportRegistry.swift`) both reference —
    /// `ContributionRegistry.sharedGraphvizRenderer` — not a fresh one.
    @Test func theSharedRendererProducesARealDiagramForPreviewDisplayFromASlicedBlock() async throws {
        let text = "```dot\ndigraph { a -> b }\n```\n"
        let document = try await ParseEngine().parse(text, revision: 0)
        let blocks = PreviewBlock.blocks(from: document, text: text)
        let graphvizBlock = try #require(blocks.first)
        let source = GraphvizFenceContent.stripDelimiters(from: graphvizBlock.source)

        let context = ContributionRegistry.graphvizRenderContext(theme: BundledThemes.light, isPrintTarget: false)
        let fence = GraphvizFence(source: source, sourceRange: 0 ..< 0)
        let diagram = try await ContributionRegistry.sharedGraphvizRenderer.render(fence, context: context)

        #expect(diagram.svg.contains("<svg"))
        #expect(diagram.naturalWidth > 0)
        #expect(diagram.naturalHeight > 0)
    }
}
