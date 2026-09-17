@testable import DiagramsD2
import Foundation
import MarkdownEngine
import Testing

@Suite("D2Contribution")
struct D2ContributionTests {
    private static let context = D2RenderContext(
        foregroundRed: 0, foregroundGreen: 0, foregroundBlue: 0,
        backgroundRed: 1, backgroundGreen: 1, backgroundBlue: 1
    )

    private static func document(_ text: String) async throws -> MarkdownDocument {
        try await ParseEngine().parse(text, revision: 0)
    }

    private struct FakeRenderer: D2DiagramRendering {
        var result: @Sendable (D2Fence) throws -> RenderedD2Diagram

        func render(_ fence: D2Fence, context _: D2RenderContext) async throws -> RenderedD2Diagram {
            try result(fence)
        }
    }

    @Test func runReturnsNothingWhenSourceHasNoD2Fence() async throws {
        let contribution = D2Contribution(context: Self.context, renderer: FakeRenderer { _ in
            RenderedD2Diagram(svg: "<svg></svg>", naturalWidth: 1, naturalHeight: 1)
        })
        let text = "no diagrams here"
        let results = try await contribution.run(document: Self.document(text), sourceText: text, sourceGeneration: 0)
        #expect(results.isEmpty)
    }

    @Test func runProducesOneHTMLResultPerFenceWithBlockPlacement() async throws {
        let contribution = D2Contribution(context: Self.context, renderer: FakeRenderer { fence in
            RenderedD2Diagram(svg: "<svg>\(fence.source)</svg>", naturalWidth: 42, naturalHeight: 24)
        })
        let text = "```d2\na -> b\n```\n"
        let results = try await contribution.run(document: Self.document(text), sourceText: text, sourceGeneration: 5)

        #expect(results.count == 1)
        let result = try #require(results.first)
        #expect(result.contributionID == "d2")
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
        let contribution = D2Contribution(context: Self.context, renderer: FakeRenderer { fence in
            if fence.source.contains("bad") {
                throw D2RenderError.invalidSyntax("unexpected token")
            }
            return RenderedD2Diagram(svg: "<svg>ok</svg>", naturalWidth: 1, naturalHeight: 1)
        })
        let text = "```d2\nbad syntax here\n```\n\n```d2\na -> b\n```\n"
        let results = try await contribution.run(document: Self.document(text), sourceText: text, sourceGeneration: 0)

        #expect(results.count == 2)
        #expect(results[0].content == nil)
        #expect(results[0].diagnostics.first?.severity == .error)
        #expect(results[1].content != nil)
    }

    @Test func runPropagatesCancellationImmediately() async throws {
        let contribution = D2Contribution(context: Self.context, renderer: FakeRenderer { _ in
            throw CancellationError()
        })
        let text = "```d2\na -> b\n```\n"
        await #expect(throws: CancellationError.self) {
            _ = try await contribution.run(document: Self.document(text), sourceText: text, sourceGeneration: 0)
        }
    }
}
