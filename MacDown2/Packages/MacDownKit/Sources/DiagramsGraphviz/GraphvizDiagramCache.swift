import CryptoKit
import Foundation

/// Bounded LRU-style cache, mirroring `MermaidDiagramCache`'s exact
/// design and rationale.
public actor GraphvizDiagramCache: GraphvizDiagramRendering {
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
        let sourceDigest: SHA256.Digest
        let paletteFingerprint: String
        let rendererVersion = "viz-js-3.30.0"
        let layoutPolicy = "dot-default-v1"
        let outputKind = "svg"
    }

    private let budget: Budget
    private let renderer: any GraphvizDiagramRendering

    private var order: [Key] = []
    private var entries: [Key: RenderedGraphvizDiagram] = [:]
    private var totalBytes = 0

    public init(budget: Budget = .standard, renderer: any GraphvizDiagramRendering) {
        self.budget = budget
        self.renderer = renderer
    }

    public func render(_ fence: GraphvizFence, context: GraphvizRenderContext) async throws -> RenderedGraphvizDiagram {
        let key = Key(
            sourceDigest: SHA256.hash(data: Data(fence.source.utf8)),
            paletteFingerprint: context.palette.fingerprint
        )
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

    private func store(key: Key, value: RenderedGraphvizDiagram) {
        // Replacing a key (two concurrent renders of one diagram) must not double-count its bytes.
        if let replaced = entries.updateValue(value, forKey: key) {
            totalBytes -= replaced.svg.utf8.count
        }
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
