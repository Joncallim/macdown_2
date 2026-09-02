import AppKit
import ExportService
import Foundation
import PDFKit
import WebKit

/// The isolated PDF adapter (issue #49 Slice 4).
///
/// It does not re-render Markdown. It loads the same self-contained HTML the
/// HTML exporter produces into a locked-down, ephemeral `WKWebView`, prints it
/// through `WKWebView.printOperation(with:)` / `NSPrintOperation` (with the
/// system `NSPrintInfo` supplying geometry), and then validates the result with
/// PDFKit before atomically promoting it into place.
///
/// The WebKit view is locked down: JavaScript is disabled, and a restrictive
/// Content-Security-Policy is injected so authored raw HTML cannot reach the
/// network — the export remains local and offline.
@MainActor
enum PDFExportAdapter {
    /// How long the page is given to lay out before the print pass is abandoned.
    /// `loadHTMLString` with no base URL cannot reach the network, so anything
    /// beyond this is a stall, not slow loading — and a stall must not leave the
    /// user with a menu that never comes back.
    private static let loadTimeout: Duration = .seconds(30)

    static func export(_ prepared: PreparedExportDocument, to url: URL) async throws {
        // Base64-encoding every embedded image is the most expensive step in a
        // PDF export; it is done off the main actor so the app stays responsive.
        let html = await hardenedHTML(from: prepared)

        let webView = WKWebView(frame: .zero, configuration: lockedConfiguration())
        let delegate = PDFNavigationDelegate()
        webView.navigationDelegate = delegate

        // An A4-ish, portrait page size; the print system supplies the real
        // pagination geometry via NSPrintInfo, so this frame only needs to be
        // non-empty for layout.
        webView.frame = NSRect(x: 0, y: 0, width: 794, height: 1123)

        // Load failures surface as themselves: they already carry prose the
        // user can act on, and wrapping them as a write failure would misname
        // what went wrong.
        try await delegate.load(html, in: webView, timeout: loadTimeout)
        try Task.checkCancellation()

        let tempURL = temporaryURL(nextTo: url)
        // The scratch file is never left behind, on any exit path.
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let printInfo = NSPrintInfo()
        printInfo.horizontalPagination = .automatic
        printInfo.verticalPagination = .automatic
        printInfo.isHorizontallyCentered = false
        printInfo.isVerticallyCentered = false

        let operation = webView.printOperation(with: printInfo)
        operation.showsPrintPanel = false
        // `run()` below blocks synchronously until pagination/rendering
        // finishes; AppKit's own progress panel (with Cancel) is the only
        // feedback available for that stretch, so it stays on even though
        // the print panel itself is suppressed.
        operation.showsProgressPanel = true
        operation.printInfo.jobDisposition = .save

        let savingKey = NSPrintInfo.AttributeKey(rawValue: "NSPrintJobSavingURL")
        operation.printInfo.dictionary()[savingKey] = tempURL

        guard operation.run() else {
            throw PDFExportError.printOperationFailed
        }

        guard let data = try? Data(contentsOf: tempURL),
              PDFDocument(data: data) != nil else {
            throw PDFExportError.invalidPDFOutput
        }

        // Atomic promotion: the validated PDF replaces any previous file.
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)
            } else {
                try FileManager.default.moveItem(at: tempURL, to: url)
            }
        } catch {
            throw ExportError.writeFailed(underlying: error)
        }
    }

    private static func lockedConfiguration() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        let pagePreferences = WKWebpagePreferences()
        pagePreferences.allowsContentJavaScript = false
        configuration.defaultWebpagePreferences = pagePreferences
        return configuration
    }

    /// The self-contained HTML with a restrictive CSP so raw authored HTML
    /// cannot fetch remote resources during the print pass.
    ///
    /// The policy is handed to the template as head content rather than
    /// substituted into the rendered string afterwards: a string rewrite would
    /// silently stop applying if the template's whitespace ever changed, and a
    /// security control that can vanish without failing is not a control.
    private nonisolated static func hardenedHTML(from prepared: PreparedExportDocument) async -> String {
        let csp = "<meta http-equiv=\"Content-Security-Policy\" content=\""
            + "default-src 'none'; script-src 'none'; style-src 'unsafe-inline'; "
            + "img-src data:; media-src data:; font-src data:; connect-src 'none'; "
            + "object-src 'none'; form-action 'none'; base-uri 'none';\">"
        return ExportHTMLWriter.selfContainedHTML(from: prepared, additionalHead: csp)
    }

    private static func temporaryURL(nextTo url: URL) -> URL {
        url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).pdf.tmp")
    }

    enum PDFExportError: Error, LocalizedError {
        case invalidPDFOutput
        case printOperationFailed
        case pageLoadTimedOut

        var errorDescription: String? {
            switch self {
            case .invalidPDFOutput: "The printed document was not a readable PDF."
            case .printOperationFailed: "The macOS print system could not produce the PDF."
            case .pageLoadTimedOut: "Laying the document out for printing took too long."
            }
        }

        var recoverySuggestion: String? {
            switch self {
            case .invalidPDFOutput, .printOperationFailed:
                "Try exporting as HTML, or print the document from the preview."
            case .pageLoadTimedOut:
                "Try again, or split very large documents before exporting."
            }
        }
    }
}

/// A navigation delegate that bridges WKWebView's callback-based load to an
/// async continuation. WKWebView invokes its delegate on the main thread, so
/// the continuation is resumed on the main actor.
@MainActor
private final class PDFNavigationDelegate: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?

    func load(_ html: String, in webView: WKWebView, timeout: Duration) async throws {
        // A watchdog guarantees the continuation is always resumed. Without it,
        // any failure WebKit reports through a delegate method this class does
        // not implement would leave the export — and the menu command driving
        // it — hung with no way back.
        let watchdog = Task { @MainActor [weak self] in
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            self?.timedOut()
        }
        defer { watchdog.cancel() }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.continuation = continuation
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    func webView(_: WKWebView, didFinish _: WKNavigation!) {
        resume(nil)
    }

    func webView(_: WKWebView, didFail _: WKNavigation!, withError error: Error) {
        resume(error)
    }

    /// The failure mode `loadHTMLString` actually reports. Without this the
    /// continuation would never be resumed and the export would hang forever.
    func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: Error) {
        resume(error)
    }

    private func timedOut() {
        resume(PDFExportAdapter.PDFExportError.pageLoadTimedOut)
    }

    private func resume(_ error: Error?) {
        guard let continuation else { return }
        self.continuation = nil
        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }
}
