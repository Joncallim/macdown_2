@testable import DiagramRendering
import Diagrams
@testable import DiagramWebKitPool
import Foundation
import Synchronization
import Testing

@MainActor
struct MermaidPoolGenerationTests {
    @Test func aNewGenerationWaitsForHeldConstructionToRetire() async throws {
        let (bundle, directory) = try makeHarnessBundle()
        defer { try? FileManager.default.removeItem(at: directory) }
        let heldPage = try await DiagramHarnessPage.make(harnessResourceName: "harness", bundle: bundle)
        defer { heldPage.teardown() }

        let entered = MermaidPoolSignal()
        let release = MermaidPoolSignal()
        let oldPool = DiagramWebKitPool(poolSize: 1, timeout: .seconds(30)) {
            await entered.fire()
            await release.wait()
            return heldPage
        }
        let constructed = Mutex(0)
        let renderer = MermaidWebRenderer(pool: oldPool, makePool: {
            constructed.withLock { $0 += 1 }
            return DiagramWebKitPool(harnessResourceName: "harness", bundle: bundle, poolSize: 1)
        })
        let fence = MermaidFence(source: "graph TD; A-->B;", sourceRange: 0 ..< 17)
        let context = MermaidRenderContext(
            foregroundRed: 0, foregroundGreen: 0, foregroundBlue: 0,
            backgroundRed: 1, backgroundGreen: 1, backgroundBlue: 1
        )
        let first = Task { try await renderer.render(fence, context: context) }
        await entered.wait()
        let shutdown = Task { await renderer.shutdown() }
        for _ in 0 ..< 1000 where await !oldPool.isShuttingDown {
            await Task.yield()
        }
        #expect(await oldPool.isShuttingDown)

        let next = Task { try await renderer.render(fence, context: context) }
        for _ in 0 ..< 20 {
            await Task.yield()
        }
        #expect(constructed.withLock { $0 } == 0)

        await release.fire()
        await shutdown.value
        #expect(heldPage.isTerminated)
        _ = try? await first.value
        let diagram = try await next.value
        #expect(diagram.pngData == Data([1, 2, 3]))
        #expect(constructed.withLock { $0 } == 1)
        await renderer.shutdown()
    }

    private func makeHarnessBundle() throws -> (Bundle, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let html = """
        <!doctype html><html><body><script>
        window.__macdownRenderMermaid = async function () {
          return {ok:true, svg:'<svg xmlns="http://www.w3.org/2000/svg"/>', png:'AQID', width:2, height:3};
        };
        </script></body></html>
        """
        try html.write(to: directory.appendingPathComponent("harness.html"), atomically: true, encoding: .utf8)
        return try (#require(Bundle(url: directory)), directory)
    }
}

private actor MermaidPoolSignal {
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
