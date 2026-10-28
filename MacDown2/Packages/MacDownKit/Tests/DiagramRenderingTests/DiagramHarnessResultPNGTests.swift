@testable import DiagramWebKitPool
import Foundation
import Testing

@MainActor
struct DiagramHarnessResultPNGTests {
    @Test func mermaidPNGSurvivesTheSharedPageCallback() async throws {
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

        let result = try await page.evaluate(
            "return {ok: true, svg: '<svg/>', png: 'AQID', width: 2, height: 3};",
            arguments: [:]
        )
        #expect(result.succeeded)
        #expect(result.svg == "<svg/>")
        #expect(result.pngBase64 == "AQID")
        #expect(try Data(base64Encoded: #require(result.pngBase64)) == Data([1, 2, 3]))
    }
}
