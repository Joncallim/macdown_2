import Foundation

/// Bounded LRU-style cache, mirroring `MermaidDiagramCache`'s exact
/// design and rationale (contributions can't cache across calls per
/// `Contributing`'s own contract, so caching lives one layer down,
/// wrapping the renderer instead).
public actor D2DiagramCache: D2DiagramRendering {
    public struct Budget: Sendable {
        public static let standard = Budget(maxEntries: 128, maxAggregateSVGBytes: 8 * 1024 * 1024)

        public let maxEntries: Int
        public let maxAggregateSVGBytes: Int

        public init(maxEntries: Int, maxAggregateSVGBytes: Int) {
            self.maxEntries = maxEntries
            self.maxAggregateSVGBytes = maxAggregateSVGBytes
        }
    }

    private struct Key: Hashable {
        let source: String
        let context: D2RenderContext
    }

    private let budget: Budget
    private let renderer: any D2DiagramRendering

    private var order: [Key] = []
    private var entries: [Key: RenderedD2Diagram] = [:]
    private var totalBytes = 0

    public init(budget: Budget = .standard, renderer: any D2DiagramRendering) {
        self.budget = budget
        self.renderer = renderer
    }

    public func render(_ fence: D2Fence, context: D2RenderContext) async throws -> RenderedD2Diagram {
        let key = Key(source: fence.source, context: context)
        if let cached = entries[key] {
            touch(key)
            return cached
        }
        let result = try await renderer.render(fence, context: context)
        store(key: key, value: result)
        return result
    }

    public var count: Int {
        entries.count
    }

    private func touch(_ key: Key) {
        if let index = order.firstIndex(of: key) {
            order.remove(at: index)
        }
        order.append(key)
    }

    private func store(key: Key, value: RenderedD2Diagram) {
        entries[key] = value
        totalBytes += value.svg.utf8.count
        touch(key)
        evictIfNeeded()
    }

    private func evictIfNeeded() {
        while order.count > budget.maxEntries || totalBytes > budget.maxAggregateSVGBytes, let oldestKey = order.first {
            order.removeFirst()
            if let removed = entries.removeValue(forKey: oldestKey) {
                totalBytes -= removed.svg.utf8.count
            }
        }
    }
}
