import AppKit
@testable import EditorCore
import FileCore
import Foundation
import Testing

/// #183 F16 — selection-only changes cause zero whole-document metric scans.
@MainActor
@Suite("EditorDocumentMetrics")
struct EditorDocumentMetricsTests {
    private func mounted(_ text: String) -> (EditorTextSystem, NSWindow) {
        let system = EditingAssistIntegrationSupport.makeSystem(text: text)
        return (system, EditingAssistIntegrationSupport.mountInWindow(system))
    }

    @Test func metricsDescribeTheDocument() {
        let metrics = EditorDocumentMetrics(of: "one two\r\nthree")
        #expect(metrics.characterCount == 13)
        #expect(metrics.wordCount == 3)
        #expect(metrics.lineEndings.uniformEnding == .crlf)
    }

    @Test func selectionOnlyChangesNeverRescanTheDocument() {
        let (system, window) = mounted("alpha beta gamma")
        defer { window.orderOut(nil) }
        _ = system.documentMetrics()
        let baseline = system.metricsCache.computationCount

        for location in 0 ... 10 {
            system.selectedRange = NSRange(location: location, length: 0)
            _ = system.documentMetrics()
        }
        system.selectedRange = NSRange(location: 2, length: 5)
        _ = system.documentMetrics()

        #expect(system.metricsCache.computationCount == baseline)
    }

    @Test func aContentChangeRecomputesExactlyOnce() {
        let (system, window) = mounted("alpha")
        defer { window.orderOut(nil) }
        _ = system.documentMetrics()
        let baseline = system.metricsCache.computationCount

        system.textView.insertText(" beta", replacementRange: NSRange(location: 5, length: 0))
        let after = system.documentMetrics()
        _ = system.documentMetrics()

        #expect(after.wordCount == 2)
        #expect(after.characterCount == 10)
        #expect(system.metricsCache.computationCount == baseline + 1)
    }

    @Test func aWholeDocumentReplacementInvalidatesTheCache() {
        let (system, window) = mounted("alpha")
        defer { window.orderOut(nil) }
        _ = system.documentMetrics()

        system.replaceTextFromExternal(
            "one\r\ntwo\r\nthree",
            preserving: system.viewportSnapshot(),
            clearUndo: true
        )

        let metrics = system.documentMetrics()
        #expect(metrics.wordCount == 3)
        #expect(metrics.lineEndings.uniformEnding == .crlf)
    }

    @Test func aSameLengthEditStillInvalidates() {
        let (system, window) = mounted("a b")
        defer { window.orderOut(nil) }
        _ = system.documentMetrics()

        system.textView.insertText("-", replacementRange: NSRange(location: 1, length: 1))

        #expect(system.documentMetrics().wordCount == 2)
        #expect(system.documentMetrics().characterCount == 3)
    }
}
