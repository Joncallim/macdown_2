import FileCore
import Foundation
@testable import MacDown2
import Testing
import WebKit

/// The HTML preview served its main document with no `Content-Type`, so WebKit reported it as not showable,
/// the host's navigation-response policy cancelled it (error 102, deliberately ignored) and the pane stayed
/// blank. This loads through the real scheme handler in a real `WKWebView`.
@MainActor
struct HTMLPreviewRenderTests {
    @Test func theMainDocumentActuallyRenders() async throws {
        let coordinator = HTMLPreviewView.Coordinator()
        let webView = coordinator.makeWebView()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("page.html")
        try "<!doctype html><html><body><p>rendered-marker</p></body></html>".write(
            to: file, atomically: true, encoding: .utf8
        )
        let document = try FileDocument(fileURL: file).load()

        coordinator.preview(document: document, in: webView)

        var text = ""
        var lastError = ""
        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        while text != "rendered-marker", ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(100))
            do {
                text = try await webView
                    .evaluateJavaScript("document.body ? document.body.innerText : ''") as? String ?? ""
            } catch {
                lastError = "\(error)"
            }
        }
        coordinator.dispose(webView: webView)

        #expect(
            text == "rendered-marker",
            "url=\(String(describing: webView.url)) loading=\(webView.isLoading) error=\(lastError)"
        )
    }
}
