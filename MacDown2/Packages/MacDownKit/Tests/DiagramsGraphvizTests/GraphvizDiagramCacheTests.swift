@testable import DiagramsGraphviz
import Foundation
import Testing

private actor CountingRenderer: GraphvizDiagramRendering {
    private(set) var callCount = 0
    var failNextCall = false

    func render(_ fence: GraphvizFence, context _: GraphvizRenderContext) async throws -> RenderedGraphvizDiagram {
        callCount += 1
        if failNextCall {
            failNextCall = false
            throw GraphvizRenderError.timedOut
        }
        return RenderedGraphvizDiagram(
            svg: "<svg><!-- \(fence.source) --></svg>",
            naturalWidth: 100,
            naturalHeight: 100
        )
    }

    func setFailNextCall(_ value: Bool) {
        failNextCall = value
    }
}

@Suite("GraphvizDiagramCache")
struct GraphvizDiagramCacheTests {
    private static let context = GraphvizRenderContext(
        foregroundRed: 0, foregroundGreen: 0, foregroundBlue: 0,
        backgroundRed: 1, backgroundGreen: 1, backgroundBlue: 1
    )

    private static func fence(_ source: String) -> GraphvizFence {
        GraphvizFence(source: source, sourceRange: 0 ..< source.count)
    }

    @Test func renderIsCachedOnIdenticalSourceAndContext() async throws {
        let counting = CountingRenderer()
        let cache = GraphvizDiagramCache(renderer: counting)

        _ = try await cache.render(Self.fence("digraph { a -> b; }"), context: Self.context)
        _ = try await cache.render(Self.fence("digraph { a -> b; }"), context: Self.context)

        #expect(await counting.callCount == 1)
    }

    @Test func aFailedRenderIsNotCached() async throws {
        let counting = CountingRenderer()
        await counting.setFailNextCall(true)
        let cache = GraphvizDiagramCache(renderer: counting)

        await #expect(throws: GraphvizRenderError.self) {
            _ = try await cache.render(Self.fence("bad"), context: Self.context)
        }
        _ = try await cache.render(Self.fence("bad"), context: Self.context)

        #expect(await counting.callCount == 2)
    }

    @Test func evictsLeastRecentlyUsedWhenEntryCountExceedsBudget() async throws {
        let counting = CountingRenderer()
        let cache = GraphvizDiagramCache(
            budget: .init(maxEntries: 2, maxAggregateSVGBytes: 1024 * 1024),
            renderer: counting
        )

        _ = try await cache.render(Self.fence("one"), context: Self.context)
        _ = try await cache.render(Self.fence("two"), context: Self.context)
        _ = try await cache.render(Self.fence("three"), context: Self.context)

        #expect(await cache.count == 2)

        _ = try await cache.render(Self.fence("one"), context: Self.context)
        #expect(await counting.callCount == 4)
    }
}
