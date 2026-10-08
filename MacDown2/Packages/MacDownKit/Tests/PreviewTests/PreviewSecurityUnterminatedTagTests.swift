import Foundation
@testable import Preview
import Testing

/// Review pass 7: when the searched `<head`/`<html` tag had no closing `>` anywhere, `scanDataState` returned without
/// advancing and `openingTagRange` spun forever on the main actor — on every open of the file and on every relaunch
/// that restored its tab.
struct PreviewSecurityUnterminatedTagTests {
    @Test(arguments: [
        "<html lang=\"en\"",
        "<!doctype html><head \n",
        "<html lang=\"en>\n<body>hi",
        "<head",
        "<html",
        "<p>x</p><head attr='unclosed",
    ])
    func anUnterminatedOpeningTagDoesNotHangTheScan(_ html: String) {
        // A plain thread and a semaphore, so a regression FAILS the test instead of hanging the whole run.
        let finished = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            _ = PreviewSecurity.hardenedHTMLDocument(from: html)
            finished.signal()
        }

        #expect(finished.wait(timeout: .now() + 10) == .success, "hardening \(html.debugDescription) did not finish")
    }

    @Test func aWellFormedDocumentStillGetsItsPolicyInTheHead() {
        let hardened = PreviewSecurity
            .hardenedHTMLDocument(from: "<html><head><title>t</title></head><body>x</body></html>")

        #expect(hardened.contains("Content-Security-Policy"))
    }
}
