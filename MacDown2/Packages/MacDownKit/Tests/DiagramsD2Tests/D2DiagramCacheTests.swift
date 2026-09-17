@testable import DiagramsD2
import Foundation
import Testing

private actor CountingRenderer: D2DiagramRendering {
    private(set) var callCount = 0
    var failNextCall = false

    func render(_ fence: D2Fence, context _: D2RenderContext) async throws -> RenderedD2Diagram {
        callCount += 1
        if failNextCall {
            failNextCall = false
            throw D2RenderError.timedOut
        }
        return RenderedD2Diagram(svg: "<svg><!-- \(fence.source) --></svg>", naturalWidth: 100, naturalHeight: 100)
    }

    func setFailNextCall(_ value: Bool) {
        failNextCall = value
    }
}

@Suite("D2DiagramCache")
struct D2DiagramCacheTests {
    private static let context = D2RenderContext(
        foregroundRed: 0, foregroundGreen: 0, foregroundBlue: 0,
        backgroundRed: 1, backgroundGreen: 1, backgroundBlue: 1
    )

    private static func fence(_ source: String) -> D2Fence {
        D2Fence(source: source, sourceRange: 0 ..< source.count)
    }

    @Test func renderIsCachedOnIdenticalSourceAndContext() async throws {
        let counting = CountingRenderer()
        let cache = D2DiagramCache(renderer: counting)

        _ = try await cache.render(Self.fence("a -> b"), context: Self.context)
        _ = try await cache.render(Self.fence("a -> b"), context: Self.context)

        #expect(await counting.callCount == 1)
    }

    @Test func aFailedRenderIsNotCached() async throws {
        let counting = CountingRenderer()
        await counting.setFailNextCall(true)
        let cache = D2DiagramCache(renderer: counting)

        await #expect(throws: D2RenderError.self) {
            _ = try await cache.render(Self.fence("bad"), context: Self.context)
        }
        _ = try await cache.render(Self.fence("bad"), context: Self.context)

        #expect(await counting.callCount == 2)
    }

    @Test func evictsLeastRecentlyUsedWhenEntryCountExceedsBudget() async throws {
        let counting = CountingRenderer()
        let cache = D2DiagramCache(
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
