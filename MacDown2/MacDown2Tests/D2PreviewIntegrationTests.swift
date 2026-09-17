import Contributions
import DiagramsD2
import Foundation
@testable import MacDown2
import MarkdownEngine
import Preview
import Testing
import Themes

/// End to end, from real parsing through to a real rendered diagram,
/// mirroring `MermaidPreviewIntegrationTests`'s exact approach
/// (epic-21-implementation.md §5 Slice 4).
@Suite("D2PreviewIntegration")
struct D2PreviewIntegrationTests {
    @Test func aRealD2FenceSlicesIntoAPreviewBlockWithTheCorrectLanguageTag() async throws {
        let text = "# Title\n\n```d2\na -> b\n```\n"
        let document = try await ParseEngine().parse(text, revision: 0)
        let blocks = PreviewBlock.blocks(from: document, text: text)

        let d2Block = try #require(blocks.first { block in
            guard case let .codeBlock(language) = block.kind else { return false }
            return language?.caseInsensitiveCompare("d2") == .orderedSame
        })
        #expect(!d2Block.isOversize)
    }

    @Test func stripDelimitersOnARealSlicedPreviewBlockRecoversExactlyTheAuthoredDiagramSource() async throws {
        let text = "```d2\na -> b\n```\n"
        let document = try await ParseEngine().parse(text, revision: 0)
        let blocks = PreviewBlock.blocks(from: document, text: text)
        let d2Block = try #require(blocks.first)

        let stripped = D2FenceContent.stripDelimiters(from: d2Block.source)
        #expect(stripped == "a -> b")
    }

    /// Uses the SAME shared instance the app's real Preview wiring
    /// (`DocumentEditorSplitView+D2Graphviz.swift`) and Export
    /// (`D2ExportRegistry.swift`) both reference —
    /// `ContributionRegistry.sharedD2Renderer` — not a fresh one.
    @Test func theSharedRendererProducesARealDiagramForPreviewDisplayFromASlicedBlock() async throws {
        let text = "```d2\na -> b\n```\n"
        let document = try await ParseEngine().parse(text, revision: 0)
        let blocks = PreviewBlock.blocks(from: document, text: text)
        let d2Block = try #require(blocks.first)
        let source = D2FenceContent.stripDelimiters(from: d2Block.source)

        let context = ContributionRegistry.d2RenderContext(theme: BundledThemes.light, isPrintTarget: false)
        let fence = D2Fence(source: source, sourceRange: 0 ..< 0)
        let diagram = try await ContributionRegistry.sharedD2Renderer.render(fence, context: context)

        #expect(diagram.svg.contains("<svg"))
        #expect(diagram.naturalWidth > 0)
        #expect(diagram.naturalHeight > 0)
    }
}
