import Contributions
import Diagrams
import Foundation
@testable import MacDown2
import MarkdownEngine
import Preview
import Testing
import Themes

/// End to end, from real parsing through to a real rendered diagram — not
/// just `MermaidFenceScanner`/`MermaidFenceContent` in isolation. Proves the
/// exact glue `TextualMarkdownPreview`'s `BlockView` relies on
/// (epic-20-implementation.md §7.2): `PreviewBlock.blocks(from:text:)`'s
/// real slicing produces a `.codeBlock(language:)` block whose source,
/// once stripped, is exactly what a real render call accepts and renders.
@Suite("MermaidPreviewIntegration")
struct MermaidPreviewIntegrationTests {
    @Test func aRealMermaidFenceSlicesIntoAPreviewBlockWithTheCorrectLanguageTag() async throws {
        let text = "# Title\n\n```mermaid\ngraph TD; A-->B;\n```\n"
        let document = try await ParseEngine().parse(text, revision: 0)
        let blocks = PreviewBlock.blocks(from: document, text: text)

        let mermaidBlock = try #require(blocks.first { block in
            guard case let .codeBlock(language) = block.kind else { return false }
            return language?.caseInsensitiveCompare("mermaid") == .orderedSame
        })
        #expect(!mermaidBlock.isOversize)
    }

    @Test func stripDelimitersOnARealSlicedPreviewBlockRecoversExactlyTheAuthoredDiagramSource() async throws {
        let text = "```mermaid\ngraph TD; A-->B;\n```\n"
        let document = try await ParseEngine().parse(text, revision: 0)
        let blocks = PreviewBlock.blocks(from: document, text: text)
        let mermaidBlock = try #require(blocks.first)

        let stripped = MermaidFenceContent.stripDelimiters(from: mermaidBlock.source)
        #expect(stripped == "graph TD; A-->B;")
    }

    /// Uses the SAME shared instance the app's real Preview wiring
    /// (`DocumentEditorSplitView.swift`) and Export
    /// (`MermaidExportRegistry.swift`) both reference —
    /// `ContributionRegistry.sharedMermaidRenderer` — not a fresh one, so
    /// this proves the actual object graph the app assembles, not a
    /// parallel one built only for this test.
    @Test func theSharedRendererProducesARealDiagramForPreviewDisplayFromASlicedBlock() async throws {
        let text = "```mermaid\ngraph TD; A-->B;\n```\n"
        let document = try await ParseEngine().parse(text, revision: 0)
        let blocks = PreviewBlock.blocks(from: document, text: text)
        let mermaidBlock = try #require(blocks.first)
        let source = MermaidFenceContent.stripDelimiters(from: mermaidBlock.source)

        let context = ContributionRegistry.mermaidRenderContext(theme: BundledThemes.light, isPrintTarget: false)
        let fence = MermaidFence(source: source, sourceRange: 0 ..< 0)
        let diagram = try await ContributionRegistry.sharedMermaidRenderer.render(fence, context: context)

        #expect(diagram.svg.contains("<svg"))
        let pngData = try #require(diagram.pngData)
        let pngMagicBytes: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        #expect(Array(pngData.prefix(8)) == pngMagicBytes)
    }
}
