import Foundation

/// Bounded LRU-style cache, keyed by (fence source, render context) equality
/// — not by document or block identity — so an unchanged diagram copy-pasted
/// into a different document, or a diagram whose surrounding prose changed
/// but whose own fence content did not, still hits the cache
/// (epic-20-implementation.md §6, §11).
///
/// `Contributing.run`'s own contract forbids a contribution from caching
/// across calls (`Contributing.swift`), so this cache lives one layer down,
/// wrapping the injected renderer — `MermaidContribution` itself stays
/// cache-free and simply receives a renderer that happens to be cached,
/// exactly the seam `MathContribution`'s injected `renderer` closure already
/// establishes for a different (uncached) reason.
///
/// A failed render is never cached: a transient timeout must not
/// permanently poison a diagram that would succeed on retry.
public actor MermaidDiagramCache: MermaidDiagramRendering {
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
        let context: MermaidRenderContext
    }

    private let budget: Budget
    private let renderer: any MermaidDiagramRendering

    /// Least-recently-used at the front, most-recently-used at the back.
    private var order: [Key] = []
    private var entries: [Key: RenderedMermaidDiagram] = [:]
    private var totalBytes = 0

    public init(budget: Budget = .standard, renderer: any MermaidDiagramRendering) {
        self.budget = budget
        self.renderer = renderer
    }

    public func render(_ fence: MermaidFence, context: MermaidRenderContext) async throws -> RenderedMermaidDiagram {
        let key = Key(source: fence.source, context: context)
        if let cached = entries[key] {
            touch(key)
            return cached
        }
        let result = try await renderer.render(fence, context: context)
        store(key: key, value: result)
        return result
    }

    /// Number of entries currently held. Test/diagnostic use.
    public var count: Int {
        entries.count
    }

    private func touch(_ key: Key) {
        if let index = order.firstIndex(of: key) {
            order.remove(at: index)
        }
        order.append(key)
    }

    private func store(key: Key, value: RenderedMermaidDiagram) {
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
