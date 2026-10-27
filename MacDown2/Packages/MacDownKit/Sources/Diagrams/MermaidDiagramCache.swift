import CryptoKit
import Foundation

/// Bounded LRU-style cache, keyed by source digest and resolved renderer policy
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
        /// Historical parameter name; bounds retained SVG and PNG bytes together.
        public let maxAggregateSVGBytes: Int

        public init(maxEntries: Int, maxAggregateSVGBytes: Int) {
            self.maxEntries = maxEntries
            self.maxAggregateSVGBytes = maxAggregateSVGBytes
        }
    }

    private struct Key: Hashable {
        let sourceDigest: SHA256.Digest
        let paletteFingerprint: String
        let rendererVersion = "mermaid-11.17.2"
        let layoutPolicy = "bundled-default-v1"
        let outputKind = "svg+png"
        let rasterScale = 2
        let rasterPolicy = "neutral-light-v1-raster-v1"
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
        let key = Key(
            sourceDigest: SHA256.hash(data: Data(fence.source.utf8)),
            paletteFingerprint: context.fingerprint
        )
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
        // Replacing a key (two concurrent renders of one diagram) must not double-count its bytes.
        if let replaced = entries.updateValue(value, forKey: key) {
            totalBytes -= retainedBytes(of: replaced)
        }
        totalBytes += retainedBytes(of: value)
        touch(key)
        evictIfNeeded()
    }

    private func evictIfNeeded() {
        while order.count > budget.maxEntries || totalBytes > budget.maxAggregateSVGBytes, let oldestKey = order.first {
            order.removeFirst()
            if let removed = entries.removeValue(forKey: oldestKey) {
                totalBytes -= retainedBytes(of: removed)
            }
        }
    }

    private func retainedBytes(of value: RenderedMermaidDiagram) -> Int {
        value.svg.utf8.count + (value.pngData?.count ?? 0)
    }
}
