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
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Int, any Error>
    }

    private let poolSize: Int
    private let timeout: Duration
    private let makePage: @Sendable () async throws -> DiagramHarnessPage

    private var slots: [DiagramHarnessPage?]
    private var busy: [Bool]
    private var waiters: [Waiter] = []
    private var constructing: [Int: Task<DiagramHarnessPage, any Error>] = [:]
    private var shutdownTask: Task<Void, Never>?
    private var closed = false

    var isShuttingDown: Bool {
        closed
    }

    public init(
        harnessResourceName: String,
        bundle: Bundle,
        poolSize: Int = 2,
        timeout: Duration = .seconds(5)
    ) {
        self.init(poolSize: poolSize, timeout: timeout) {
            try await DiagramHarnessPage.make(harnessResourceName: harnessResourceName, bundle: bundle)
        }
    }

    /// Allows lifecycle tests to hold construction at a precise suspension point.
    /// Production always uses the bundled, contained harness factory above.
    init(
        poolSize: Int,
        timeout: Duration,
        makePage: @escaping @Sendable () async throws -> DiagramHarnessPage
    ) {
        self.poolSize = max(1, poolSize)
        self.timeout = timeout
        self.makePage = makePage
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
        let index = try await checkout()
        let page: DiagramHarnessPage
        do {
            try Task.checkCancellation()
            page = try await self.page(at: index)
            guard !closed else { throw DiagramPoolError.pageUnavailable }
        } catch {
            checkin(index)
            throw error
        }
        do {
            let result = try await DiagramTimeoutRace.run(
                timeout: timeout,
                timeoutError: DiagramPoolError.timedOut
            ) { try await body(page) }
            guard !closed else { throw DiagramPoolError.pageUnavailable }
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
        if let shutdownTask {
            await shutdownTask.value
            return
        }
        guard !closed else { return }
        closed = true
        let queued = waiters
        waiters.removeAll()
        for waiter in queued {
            waiter.continuation.resume(throwing: DiagramPoolError.pageUnavailable)
        }
        let pages = slots.compactMap(\.self)
        let builds = Array(constructing.values)
        constructing.removeAll()
        slots = Array(repeating: nil, count: poolSize)
        let task = Task {
            for build in builds {
                build.cancel()
            }
            for page in pages {
                await page.teardown()
            }
            for build in builds {
                if case let .success(page) = await build.result {
                    await page.teardown()
                }
            }
        }
        shutdownTask = task
        await task.value
        shutdownTask = nil
    }

    private func page(at index: Int) async throws -> DiagramHarnessPage {
        guard !closed else { throw DiagramPoolError.pageUnavailable }
        if let existing = slots[index] {
            if await !existing.isTerminated {
                guard !closed else { throw DiagramPoolError.pageUnavailable }
                return existing
            }
            await existing.teardown()
            slots[index] = nil
        }
        guard !closed else { throw DiagramPoolError.pageUnavailable }
        let factory = makePage
        let construction = Task { try await factory() }
        constructing[index] = construction
        let page: DiagramHarnessPage
        do {
            page = try await withTaskCancellationHandler {
                try await construction.value
            } onCancel: {
                construction.cancel()
            }
        } catch {
            constructing[index] = nil
            throw error
        }
        constructing[index] = nil
        guard !closed else {
            // Shutdown owns every registered construction, including this page.
            throw DiagramPoolError.pageUnavailable
        }
        if Task.isCancelled {
            await page.teardown()
            throw CancellationError()
        }
        slots[index] = page
        return page
    }

    private func checkout() async throws -> Int {
        try Task.checkCancellation()
        guard !closed else { throw DiagramPoolError.pageUnavailable }
        if let index = busy.firstIndex(of: false) {
            busy[index] = true
            return index
        }
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiters.append(Waiter(id: id, continuation: continuation))
            }
        } onCancel: {
            Task { await self.cancelCheckout(id) }
        }
    }

    private func cancelCheckout(_ id: UUID) {
        guard let position = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: position).continuation.resume(throwing: CancellationError())
    }

    /// Hands the slot directly to the next waiter if one is queued (it
    /// stays marked busy — ownership transfers without ever appearing
    /// free); otherwise marks it free.
    private func checkin(_ index: Int) {
        guard !closed else {
            busy[index] = false
            return
        }
        guard waiters.isEmpty else {
            let waiter = waiters.removeFirst()
            waiter.continuation.resume(returning: index)
            return
        }
        busy[index] = false
    }
}
