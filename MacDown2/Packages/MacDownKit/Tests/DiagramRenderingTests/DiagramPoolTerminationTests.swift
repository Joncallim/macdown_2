import DiagramWebKitPool
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
}
