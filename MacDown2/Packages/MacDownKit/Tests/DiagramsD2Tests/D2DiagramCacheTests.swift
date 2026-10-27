@testable import DiagramsD2
import Foundation
import Testing
@testable import Themes

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

    @Test func appThemeVariantsShareTheResolvedNeutralArtwork() async throws {
        let counting = CountingRenderer()
        let cache = D2DiagramCache(renderer: counting)
        let dark = D2RenderContext(
            foregroundRed: 1, foregroundGreen: 1, foregroundBlue: 1,
            backgroundRed: 0, backgroundGreen: 0, backgroundBlue: 0
        )
        #expect(dark.palette == Self.context.palette)

        _ = try await cache.render(Self.fence("a -> b"), context: Self.context)
        _ = try await cache.render(Self.fence("a -> b"), context: dark)

        #expect(await counting.callCount == 1)
    }

    @Test func policyFingerprintChangeCannotReuseAnOldDiagram() async throws {
        let counting = CountingRenderer()
        let cache = D2DiagramCache(renderer: counting)
        let updated = DiagramPalette(
            policyID: "neutral-light-v2", canvas: "#FFFFFF", text: "#1A1A1A", stroke: "#1A1A1A",
            nodeFill: "#F3F5F8", accent: "#285EA8", secondary: "#526274"
        )
        _ = try await cache.render(Self.fence("a -> b"), context: .neutralLight)
        _ = try await cache.render(Self.fence("a -> b"), context: D2RenderContext(palette: updated))
        #expect(await counting.callCount == 2)
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
