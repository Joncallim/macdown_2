import Diagrams
import Foundation

/// The real, WebKit-backed implementation of `MermaidDiagramRendering`
/// (epic-20-implementation.md §6, §11). Owns a small, bounded pool of
/// `MermaidHarnessPage`s — offscreen web views, never displayed — created
/// lazily and reused across many render calls (pool warm-up, i.e. loading
/// the Mermaid harness into a fresh page, is the expensive part; nothing
/// about a single document owns the pool exclusively, so it is
/// process-lifetime, torn down only by an explicit `shutdown()` call, not
/// per-document).
///
/// An `actor` so concurrent render calls are safely distributed across the
/// pool without a caller needing to reason about `WKWebView`'s own
/// main-thread affinity. Checkout/checkin uses a simple continuation-based
/// wait queue rather than a fixed thread/dispatch semaphore, matching this
/// package's other actor-based concurrency (`Contributing`'s own
/// cancellation contract; the generation-token idiom recurring elsewhere in
/// this codebase, epic-20-implementation.md §2.1) rather than introducing a
/// new concurrency primitive.
public actor MermaidWebRenderer: MermaidDiagramRendering {
    /// Provisional pending real-diagram calibration (§11, §18) — not a
    /// value with independent architectural significance.
    public static let defaultMaxOutputBytes = 2 * 1024 * 1024

    private let poolSize: Int
    private let timeout: Duration
    private let maxOutputBytes: Int

    private var slots: [MermaidHarnessPage?]
    private var busy: [Bool]
    private var waiters: [CheckedContinuation<Int, Never>] = []

    public init(
        poolSize: Int = 2,
        timeout: Duration = .seconds(5),
        maxOutputBytes: Int = MermaidWebRenderer.defaultMaxOutputBytes
    ) {
        self.poolSize = max(1, poolSize)
        self.timeout = timeout
        self.maxOutputBytes = maxOutputBytes
        slots = Array(repeating: nil, count: self.poolSize)
        busy = Array(repeating: false, count: self.poolSize)
    }

    /// `context`'s theme colors are accepted (matching the
    /// `MermaidDiagramRendering` contract every caller/cache/contribution
    /// keys against) but not yet passed through to Mermaid's own theming —
    /// Slice 2's scope is the render pipeline, timeout, output ceiling, and
    /// security containment (epic-20-implementation.md §17 Slice 2), not
    /// color-accurate theme matching. Every diagram currently renders with
    /// Mermaid's own default theme regardless of the app's active theme.
    /// Deliberate, not an oversight — tracked as residual work (§18) rather
    /// than silently dropped.
    public func render(_ fence: MermaidFence, context _: MermaidRenderContext) async throws -> RenderedMermaidDiagram {
        let index = await checkout()
        defer { checkin(index) }
        let page = try await page(at: index)
        let diagram = try await withTimeout(timeout) {
            try await page.render(fence.source)
        }
        let byteCount = diagram.svg.utf8.count
        guard byteCount <= maxOutputBytes else {
            throw MermaidRenderError.outputTooLarge(byteCount: byteCount)
        }
        return diagram
    }

    /// Tears down every pooled page. Called on app termination and in
    /// tests; not required between individual documents.
    public func shutdown() async {
        for case let page? in slots {
            await page.teardown()
        }
        slots = Array(repeating: nil, count: poolSize)
    }

    private func page(at index: Int) async throws -> MermaidHarnessPage {
        if let existing = slots[index] {
            return existing
        }
        let page = try await MermaidHarnessPage.make()
        slots[index] = page
        return page
    }

    private func checkout() async -> Int {
        if let index = busy.firstIndex(of: false) {
            busy[index] = true
            return index
        }
        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    /// Hands the slot directly to the next waiter if one is queued (it stays
    /// marked busy — ownership transfers without ever appearing free);
    /// otherwise marks it free.
    private func checkin(_ index: Int) {
        guard waiters.isEmpty else {
            let continuation = waiters.removeFirst()
            continuation.resume(returning: index)
            return
        }
        busy[index] = false
    }

    /// Races `operation` against a timeout, matching the accepted, bounded
    /// cancellation limitation described in §8: this stops the *caller* from
    /// waiting past `timeout`, it does not abort JavaScript already
    /// dispatched to the page — the same accepted shape as
    /// `MathImageRenderer`'s uninterruptible render call.
    private func withTimeout<T: Sendable>(
        _ duration: Duration,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: duration)
                throw MermaidRenderError.timedOut
            }
            guard let result = try await group.next() else {
                throw MermaidRenderError.timedOut
            }
            group.cancelAll()
            return result
        }
    }
}
