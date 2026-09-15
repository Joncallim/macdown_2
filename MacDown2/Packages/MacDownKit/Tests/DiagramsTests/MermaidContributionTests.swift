@testable import Diagrams
import Foundation
import MarkdownEngine
import Testing

@Suite("MermaidContribution")
struct MermaidContributionTests {
    private static let context = MermaidRenderContext(
        foregroundRed: 0, foregroundGreen: 0, foregroundBlue: 0,
        backgroundRed: 1, backgroundGreen: 1, backgroundBlue: 1
    )

    private static func document(_ text: String) async throws -> MarkdownDocument {
        try await ParseEngine().parse(text, revision: 0)
    }

    private struct FakeRenderer: MermaidDiagramRendering {
        var result: @Sendable (MermaidFence) throws -> RenderedMermaidDiagram

        func render(_ fence: MermaidFence, context _: MermaidRenderContext) async throws -> RenderedMermaidDiagram {
            try result(fence)
        }
    }

    @Test func runReturnsNothingWhenSourceHasNoMermaidFence() async throws {
        let contribution = MermaidContribution(context: Self.context, renderer: FakeRenderer { _ in
            RenderedMermaidDiagram(svg: "<svg></svg>", naturalWidth: 1, naturalHeight: 1)
        })
        let text = "no diagrams here"
        let results = try await contribution.run(document: Self.document(text), sourceText: text, sourceGeneration: 0)
        #expect(results.isEmpty)
    }

    @Test func runProducesOneHTMLResultPerFenceWithBlockPlacement() async throws {
        let contribution = MermaidContribution(context: Self.context, renderer: FakeRenderer { fence in
            RenderedMermaidDiagram(svg: "<svg>\(fence.source)</svg>", naturalWidth: 42, naturalHeight: 24)
        })
        let text = "```mermaid\ngraph TD; A-->B;\n```\n"
        let results = try await contribution.run(document: Self.document(text), sourceText: text, sourceGeneration: 5)

        #expect(results.count == 1)
        let result = try #require(results.first)
        #expect(result.contributionID == "mermaid")
        #expect(result.sourceGeneration == 5)
        #expect(result.diagnostics.isEmpty)
        #expect(result.content?.placement == .block)
        guard case let .html(svg) = result.content?.representation else {
            Issue.record("expected .html representation")
            return
        }
        #expect(svg.contains("graph TD; A-->B;"))
    }

    @Test func runIsolatesAFailedFenceWithoutAffectingOthers() async throws {
        let contribution = MermaidContribution(context: Self.context, renderer: FakeRenderer { fence in
            if fence.source.contains("bad") {
                throw MermaidRenderError.invalidSyntax("unexpected token")
            }
            return RenderedMermaidDiagram(svg: "<svg>ok</svg>", naturalWidth: 1, naturalHeight: 1)
        })
        let text = "```mermaid\nbad syntax here\n```\n\n```mermaid\ngraph TD; A-->B;\n```\n"
        let results = try await contribution.run(document: Self.document(text), sourceText: text, sourceGeneration: 0)

        #expect(results.count == 2)
        #expect(results[0].content == nil)
        #expect(results[0].diagnostics.first?.severity == .error)
        #expect(results[0].diagnostics.first?.message.contains("unexpected token") == true)
        #expect(results[1].content != nil)
    }

    @Test func runPropagatesCancellationImmediately() async throws {
        let contribution = MermaidContribution(context: Self.context, renderer: FakeRenderer { _ in
            throw CancellationError()
        })
        let text = "```mermaid\ngraph TD; A-->B;\n```\n"
        await #expect(throws: CancellationError.self) {
            _ = try await contribution.run(document: Self.document(text), sourceText: text, sourceGeneration: 0)
        }
    }
}
