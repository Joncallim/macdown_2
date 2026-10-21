@testable import DiagramWebKitPool
import Foundation
import Testing
import WebKit

/// There was no `webViewWebContentProcessDidTerminate` handler anywhere, so a page whose WebContent process died
/// stayed in the pool and every later render through that slot failed until relaunch.
@MainActor
struct DiagramPoolTerminationTests {
    private func makeHarnessBundle() throws -> (bundle: Bundle, directory: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "<!doctype html><html><body>harness</body></html>".write(
            to: directory.appendingPathComponent("harness.html"), atomically: true, encoding: .utf8
        )
        return try (#require(Bundle(url: directory)), directory)
    }

    @Test func aTerminatedPageIsReplacedByTheNextCheckout() async throws {
        let (bundle, directory) = try makeHarnessBundle()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pool = DiagramWebKitPool(harnessResourceName: "harness", bundle: bundle, poolSize: 1, timeout: .seconds(30))

        let first = try await pool.withPage { page in
            await MainActor.run { () -> ObjectIdentifier in
                // What WebKit calls when the content process dies.
                page.webViewWebContentProcessDidTerminate(WKWebView())
                return ObjectIdentifier(page)
            }
        }
        let second = try await pool.withPage { page in
            await MainActor.run { (ObjectIdentifier(page), page.isTerminated) }
        }

        #expect(second.0 != first)
        #expect(second.1 == false)
        await pool.shutdown()
    }

    @Test func aHealthyPageIsReusedAsBefore() async throws {
        let (bundle, directory) = try makeHarnessBundle()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pool = DiagramWebKitPool(harnessResourceName: "harness", bundle: bundle, poolSize: 1, timeout: .seconds(30))

        let first = try await pool.withPage { page in await MainActor.run { ObjectIdentifier(page) } }
        let second = try await pool.withPage { page in await MainActor.run { ObjectIdentifier(page) } }

        #expect(first == second)
        await pool.shutdown()
    }

    @Test func queuedRenderCannotReopenAPoolAfterShutdown() async throws {
        let (bundle, directory) = try makeHarnessBundle()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pool = DiagramWebKitPool(harnessResourceName: "harness", bundle: bundle, poolSize: 1)
        let entered = DiagramPoolTestSignal()
        let release = DiagramPoolTestSignal()

        let first = Task {
            try await pool.withPage { _ in
                await entered.fire()
                await release.wait()
            }
        }
        await entered.wait()
        let queued = Task { try await pool.withPage { _ in 42 } }

        await pool.shutdown()
        await release.fire()
        _ = try? await first.value
        do {
            _ = try await queued.value
            Issue.record("a queued request reopened the pool after terminal shutdown")
        } catch {
            #expect(error as? DiagramPoolError == .pageUnavailable)
        }
    }

    @Test func cancellingAQueuedRenderSettlesBeforeItsSlotIsReleased() async throws {
        let (bundle, directory) = try makeHarnessBundle()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pool = DiagramWebKitPool(harnessResourceName: "harness", bundle: bundle, poolSize: 1)
        let entered = DiagramPoolTestSignal()
        let release = DiagramPoolTestSignal()

        let first = Task {
            try await pool.withPage { _ in
                await entered.fire()
                await release.wait()
            }
        }
        await entered.wait()
        let queued = Task { try await pool.withPage { _ in 42 } }
        queued.cancel()

        let outcome: Result<Int, any Error>
        do {
            outcome = try await .success(DiagramTimeoutRace.run(
                timeout: .seconds(2),
                timeoutError: DiagramPoolError.timedOut
            ) { try await queued.value })
        } catch {
            outcome = .failure(error)
        }
        await release.fire()
        _ = try? await first.value
        _ = try? await queued.value
        switch outcome {
        case .success:
            Issue.record("a cancelled request waited for the occupied page")
        case let .failure(error):
            #expect(error is CancellationError)
        }
        await pool.shutdown()
    }

    @Test func teardownSettlesAnEvaluatingPageBeforeWebKitCompletes() async throws {
        let (bundle, directory) = try makeHarnessBundle()
        defer { try? FileManager.default.removeItem(at: directory) }
        let page = try await DiagramHarnessPage.make(harnessResourceName: "harness", bundle: bundle)
        let evaluation = Task {
            _ = try await page.evaluate("return await new Promise(() => {});", arguments: [:])
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while page.pendingEvaluationCount == 0, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(page.pendingEvaluationCount == 1)
        page.teardown()
        do {
            _ = try await DiagramTimeoutRace.run(
                timeout: .seconds(2),
                timeoutError: DiagramPoolError.timedOut
            ) { try await evaluation.value }
            Issue.record("teardown published a late evaluation")
        } catch {
            #expect(error as? DiagramPoolError == .pageUnavailable)
        }
        #expect(page.pendingEvaluationCount == 0)
    }

    @Test func cancellationSettlesAnEvaluatingPageWithoutWaitingForJavaScript() async throws {
        let (bundle, directory) = try makeHarnessBundle()
        defer { try? FileManager.default.removeItem(at: directory) }
        let page = try await DiagramHarnessPage.make(harnessResourceName: "harness", bundle: bundle)
        let evaluation = Task {
            _ = try await page.evaluate("return await new Promise(() => {});", arguments: [:])
        }
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while page.pendingEvaluationCount == 0, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(page.pendingEvaluationCount == 1)
        evaluation.cancel()
        do {
            _ = try await DiagramTimeoutRace.run(
                timeout: .seconds(2),
                timeoutError: DiagramPoolError.timedOut
            ) { try await evaluation.value }
            Issue.record("cancellation waited for the unending JavaScript promise")
        } catch {
            #expect(error is CancellationError)
        }
        #expect(page.pendingEvaluationCount == 0)
        page.teardown()
    }
}

private actor DiagramPoolTestSignal {
    private var fired = false
    private var waiter: CheckedContinuation<Void, Never>?

    func wait() async {
        if fired {
            return
        }
        await withCheckedContinuation { waiter = $0 }
    }

    func fire() {
        fired = true
        waiter?.resume()
        waiter = nil
    }
}
