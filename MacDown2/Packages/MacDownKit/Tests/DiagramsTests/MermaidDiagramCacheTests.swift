@testable import Diagrams
import Foundation
import Testing

private actor CountingRenderer: MermaidDiagramRendering {
    private(set) var callCount = 0
    private(set) var lastFence: MermaidFence?
    var failNextCall = false

    func render(_ fence: MermaidFence, context _: MermaidRenderContext) async throws -> RenderedMermaidDiagram {
        callCount += 1
        lastFence = fence
        if failNextCall {
            failNextCall = false
            throw MermaidRenderError.timedOut
        }
        return RenderedMermaidDiagram(
            svg: "<svg><!-- \(fence.source) --></svg>",
            pngData: nil,
            naturalWidth: 100,
            naturalHeight: 100
        )
    }
}

@Suite("MermaidDiagramCache")
struct MermaidDiagramCacheTests {
    private static let context = MermaidRenderContext(
        foregroundRed: 0, foregroundGreen: 0, foregroundBlue: 0,
        backgroundRed: 1, backgroundGreen: 1, backgroundBlue: 1
    )

    private static func fence(_ source: String) -> MermaidFence {
        MermaidFence(source: source, sourceRange: 0 ..< source.count)
    }

    @Test func renderIsCachedOnIdenticalSourceAndContext() async throws {
        let counting = CountingRenderer()
        let cache = MermaidDiagramCache(renderer: counting)

        _ = try await cache.render(Self.fence("graph TD; A-->B;"), context: Self.context)
        _ = try await cache.render(Self.fence("graph TD; A-->B;"), context: Self.context)

        #expect(await counting.callCount == 1)
    }

    @Test func differentSourceIsNotCachedTogether() async throws {
        let counting = CountingRenderer()
        let cache = MermaidDiagramCache(renderer: counting)

        _ = try await cache.render(Self.fence("graph TD; A-->B;"), context: Self.context)
        _ = try await cache.render(Self.fence("graph TD; B-->A;"), context: Self.context)

        #expect(await counting.callCount == 2)
    }

    @Test func differentContextIsNotCachedTogether() async throws {
        let counting = CountingRenderer()
        let cache = MermaidDiagramCache(renderer: counting)
        let otherContext = MermaidRenderContext(
            foregroundRed: 1, foregroundGreen: 1, foregroundBlue: 1,
            backgroundRed: 0, backgroundGreen: 0, backgroundBlue: 0
        )

        _ = try await cache.render(Self.fence("graph TD; A-->B;"), context: Self.context)
        _ = try await cache.render(Self.fence("graph TD; A-->B;"), context: otherContext)

        #expect(await counting.callCount == 2)
    }

    @Test func aFailedRenderIsNotCached() async throws {
        let counting = CountingRenderer()
        await counting.setFailNextCall(true)
        let cache = MermaidDiagramCache(renderer: counting)

        await #expect(throws: MermaidRenderError.self) {
            _ = try await cache.render(Self.fence("bad"), context: Self.context)
        }
        _ = try await cache.render(Self.fence("bad"), context: Self.context)

        #expect(await counting.callCount == 2)
    }

    @Test func evictsLeastRecentlyUsedWhenEntryCountExceedsBudget() async throws {
        let counting = CountingRenderer()
        let cache = MermaidDiagramCache(
            budget: .init(maxEntries: 2, maxAggregateSVGBytes: 1024 * 1024),
            renderer: counting
        )

        _ = try await cache.render(Self.fence("one"), context: Self.context)
        _ = try await cache.render(Self.fence("two"), context: Self.context)
        _ = try await cache.render(Self.fence("three"), context: Self.context)

        #expect(await cache.count == 2)

        // "one" was evicted; re-requesting it renders again.
        _ = try await cache.render(Self.fence("one"), context: Self.context)
        #expect(await counting.callCount == 4)
    }

    @Test func recentlyTouchedEntriesSurviveEvictionOverOlderUnusedOnes() async throws {
        let counting = CountingRenderer()
        let cache = MermaidDiagramCache(
            budget: .init(maxEntries: 2, maxAggregateSVGBytes: 1024 * 1024),
            renderer: counting
        )

        _ = try await cache.render(Self.fence("one"), context: Self.context)
        _ = try await cache.render(Self.fence("two"), context: Self.context)
        // Touch "one" again so "two" becomes the least-recently-used entry.
        _ = try await cache.render(Self.fence("one"), context: Self.context)
        _ = try await cache.render(Self.fence("three"), context: Self.context)

        // "two" was evicted, not "one".
        _ = try await cache.render(Self.fence("one"), context: Self.context)
        #expect(await counting.callCount == 3)
    }

    @Test func evictsWhenAggregateByteBudgetIsExceeded() async throws {
        let counting = CountingRenderer()
        // Each rendered SVG is ~30 bytes; force eviction well before 128 entries.
        let cache = MermaidDiagramCache(
            budget: .init(maxEntries: 128, maxAggregateSVGBytes: 40),
            renderer: counting
        )

        _ = try await cache.render(Self.fence("one"), context: Self.context)
        _ = try await cache.render(Self.fence("two"), context: Self.context)

        #expect(await cache.count < 2)
    }
}

private extension CountingRenderer {
    func setFailNextCall(_ value: Bool) {
        failNextCall = value
    }
}
