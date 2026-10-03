import Foundation

/// A bounded pool of `DiagramHarnessPage`s, generalized from
/// `MermaidWebRenderer`'s own pool/checkout/checkin/timeout logic
/// (epic-20-implementation.md §11) — extracted here because that part,
/// unlike JS invocation shape or result parsing, is genuinely identical
/// across every renderer built on `DiagramHarnessPage`
/// (epic-21-implementation.md §3.1). Each language's own renderer owns
/// one `DiagramWebKitPool` instance and its own bundled harness resource;
/// this type knows nothing about what JS a particular language runs.
///
/// Process-lifetime by design, not document-lifetime — pool warm-up
/// (loading a harness into a fresh page) is the expensive part, and
/// nothing about a single document owns a pool exclusively.
public actor DiagramWebKitPool {
    private let poolSize: Int
    private let timeout: Duration
    private let harnessResourceName: String
    private let bundle: Bundle

    private var slots: [DiagramHarnessPage?]
    private var busy: [Bool]
    private var waiters: [CheckedContinuation<Int, Never>] = []

    public init(
        harnessResourceName: String,
        bundle: Bundle,
        poolSize: Int = 2,
        timeout: Duration = .seconds(5)
    ) {
        self.harnessResourceName = harnessResourceName
        self.bundle = bundle
        self.poolSize = max(1, poolSize)
        self.timeout = timeout
        slots = Array(repeating: nil, count: self.poolSize)
        busy = Array(repeating: false, count: self.poolSize)
    }

    /// Checks out a page, runs `body` against it racing the configured timeout, and
    /// returns the page to the pool (or hands it directly to the next waiter). A page whose
    /// script outlived the timeout, or whose caller was cancelled mid-run, may still be
    /// executing, so it is torn down and replaced rather than handed to the next render.
    public func withPage<T: Sendable>(
        _ body: @escaping @Sendable (DiagramHarnessPage) async throws -> T
    ) async throws -> T {
        let index = await checkout()
        let page: DiagramHarnessPage
        do {
            page = try await self.page(at: index)
        } catch {
            checkin(index)
            throw error
        }
        do {
            let result = try await DiagramTimeoutRace.run(
                timeout: timeout,
                timeoutError: DiagramPoolError.timedOut
            ) { try await body(page) }
            checkin(index)
            return result
        } catch {
            if error is CancellationError || (error as? DiagramPoolError) == .timedOut {
                slots[index] = nil
                await page.teardown()
            }
            checkin(index)
            throw error
        }
    }

    /// Tears down every pooled page. Called on app termination and in
    /// tests; not required between individual documents.
    public func shutdown() async {
        for case let page? in slots {
            await page.teardown()
        }
        slots = Array(repeating: nil, count: poolSize)
    }

    private func page(at index: Int) async throws -> DiagramHarnessPage {
        if let existing = slots[index] {
            return existing
        }
        let page = try await DiagramHarnessPage.make(harnessResourceName: harnessResourceName, bundle: bundle)
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

    /// Hands the slot directly to the next waiter if one is queued (it
    /// stays marked busy — ownership transfers without ever appearing
    /// free); otherwise marks it free.
    private func checkin(_ index: Int) {
        guard waiters.isEmpty else {
            let continuation = waiters.removeFirst()
            continuation.resume(returning: index)
            return
        }
        busy[index] = false
    }
}
