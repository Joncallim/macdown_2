@testable import DiagramWebKitPool
import Foundation
import Testing

@MainActor
struct DiagramPoolRetirementTests {
    @Test func shutdownDrainsAPageAlreadyRemovedForRetirement() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try "<!doctype html><html><body>harness</body></html>".write(
            to: directory.appendingPathComponent("harness.html"), atomically: true, encoding: .utf8
        )
        let bundle = try #require(Bundle(url: directory))
        let page = try await DiagramHarnessPage.make(harnessResourceName: "harness", bundle: bundle)
        defer { page.teardown() }
        let retiring = RetirementSignal()
        let release = RetirementSignal()
        let completed = RetirementSignal()
        let pool = DiagramWebKitPool(poolSize: 1, timeout: .seconds(30), makePage: { page }, retirePage: { page in
            await retiring.fire()
            await release.wait()
            await page.teardown()
        })

        let render = Task { try await pool.withPage { _ -> Int in throw CancellationError() } }
        await retiring.wait()
        let shutdown = Task {
            await pool.shutdown()
            await completed.fire()
        }
        for _ in 0 ..< 1000 where await !pool.isShuttingDown {
            await Task.yield()
        }
        #expect(await pool.isShuttingDown)
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        #expect(await !completed.hasFired)

        await release.fire()
        await shutdown.value
        _ = try? await render.value
        #expect(page.isTerminated)
        #expect(await completed.hasFired)
    }
}

private actor RetirementSignal {
    private var fired = false
    private var waiter: CheckedContinuation<Void, Never>?

    var hasFired: Bool {
        fired
    }

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
