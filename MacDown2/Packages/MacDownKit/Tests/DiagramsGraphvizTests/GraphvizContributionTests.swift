@testable import DiagramsGraphviz
import Foundation
import MarkdownEngine
import Testing

@Suite("GraphvizContribution")
struct GraphvizContributionTests {
    private static let context = GraphvizRenderContext(
        foregroundRed: 0, foregroundGreen: 0, foregroundBlue: 0,
        backgroundRed: 1, backgroundGreen: 1, backgroundBlue: 1
    )

    private static func document(_ text: String) async throws -> MarkdownDocument {
        try await ParseEngine().parse(text, revision: 0)
    }

    private struct FakeRenderer: GraphvizDiagramRendering {
        var result: @Sendable (GraphvizFence) throws -> RenderedGraphvizDiagram

        func render(_ fence: GraphvizFence, context _: GraphvizRenderContext) async throws -> RenderedGraphvizDiagram {
            try result(fence)
        }
    }

    @Test func runReturnsNothingWhenSourceHasNoGraphvizFence() async throws {
        let contribution = GraphvizContribution(context: Self.context, renderer: FakeRenderer { _ in
            RenderedGraphvizDiagram(svg: "<svg></svg>", naturalWidth: 1, naturalHeight: 1)
        })
        let text = "no diagrams here"
        let results = try await contribution.run(document: Self.document(text), sourceText: text, sourceGeneration: 0)
        #expect(results.isEmpty)
    }

    @Test func runProducesOneHTMLResultPerFenceWithBlockPlacement() async throws {
        let contribution = GraphvizContribution(context: Self.context, renderer: FakeRenderer { fence in
            RenderedGraphvizDiagram(svg: "<svg>\(fence.source)</svg>", naturalWidth: 42, naturalHeight: 24)
        })
        let text = "```dot\ndigraph { a -> b; }\n```\n"
        let results = try await contribution.run(document: Self.document(text), sourceText: text, sourceGeneration: 5)

        #expect(results.count == 1)
        let result = try #require(results.first)
        #expect(result.contributionID == "graphviz")
        #expect(result.sourceGeneration == 5)
        #expect(result.diagnostics.isEmpty)
        #expect(result.content?.placement == .block)
        guard case let .html(svg) = result.content?.representation else {
            Issue.record("expected .html representation")
            return
        }
        #expect(svg.contains("a -> b"))
    }

    @Test func runIsolatesAFailedFenceWithoutAffectingOthers() async throws {
        let contribution = GraphvizContribution(context: Self.context, renderer: FakeRenderer { fence in
            if fence.source.contains("bad") {
                throw GraphvizRenderError.invalidSyntax("unexpected token")
            }
            return RenderedGraphvizDiagram(svg: "<svg>ok</svg>", naturalWidth: 1, naturalHeight: 1)
        })
        let text = "```dot\nbad syntax here\n```\n\n```dot\ndigraph { a -> b; }\n```\n"
        let results = try await contribution.run(document: Self.document(text), sourceText: text, sourceGeneration: 0)

        #expect(results.count == 2)
        #expect(results[0].content == nil)
        #expect(results[0].diagnostics.first?.severity == .error)
        #expect(results[1].content != nil)
    }

    @Test func runPropagatesCancellationImmediately() async throws {
        let contribution = GraphvizContribution(context: Self.context, renderer: FakeRenderer { _ in
            throw CancellationError()
        })
        let text = "```dot\ndigraph { a -> b; }\n```\n"
        await #expect(throws: CancellationError.self) {
            _ = try await contribution.run(document: Self.document(text), sourceText: text, sourceGeneration: 0)
        }
    }
}
