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
    static func export(_ prepared: PreparedExportDocument, to url: URL) async throws {
        let html = hardenedHTML(from: prepared)
        let webView = WKWebView(frame: .zero, configuration: lockedConfiguration())
        let delegate = PDFNavigationDelegate()
        webView.navigationDelegate = delegate

        // An A4-ish, portrait page size; the print system supplies the real
        // pagination geometry via NSPrintInfo, so this frame only needs to be
        // non-empty for layout.
        webView.frame = NSRect(x: 0, y: 0, width: 794, height: 1123)

        try await delegate.load(html, in: webView)

        let printInfo = NSPrintInfo()
        printInfo.horizontalPagination = .automatic
        printInfo.verticalPagination = .automatic
        printInfo.isHorizontallyCentered = false
        printInfo.isVerticallyCentered = false

        let operation = webView.printOperation(with: printInfo)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        operation.printInfo.jobDisposition = .save

        let tempURL = temporaryURL(nextTo: url)
        let savingKey = NSPrintInfo.AttributeKey(rawValue: "NSPrintJobSavingURL")
        operation.printInfo.dictionary()[savingKey] = tempURL

        operation.run()

        guard let data = try? Data(contentsOf: tempURL),
              PDFDocument(data: data) != nil else {
            throw ExportError.writeFailed(underlying: PDFExportError.invalidPDFOutput)
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
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        let pagePreferences = WKWebpagePreferences()
        pagePreferences.allowsContentJavaScript = false
        configuration.defaultWebpagePreferences = pagePreferences
        return configuration
    }

    /// The self-contained HTML with a restrictive CSP so raw authored HTML
    /// cannot fetch remote resources during the print pass.
    private static func hardenedHTML(from prepared: PreparedExportDocument) -> String {
        let html = ExportHTMLWriter.selfContainedHTML(from: prepared)
        let csp = "<meta http-equiv=\"Content-Security-Policy\" content=\""
            + "default-src 'none'; script-src 'none'; style-src 'unsafe-inline'; "
            + "img-src data:; media-src data:; font-src data:; connect-src 'none'; "
            + "object-src 'none'; form-action 'none'; base-uri 'none';\">\n"
        // The template's head begins with "<head>\n"; the title is already
        // HTML-escaped, so injecting directly after it is safe and governs the
        // whole document.
        return html.replacingOccurrences(of: "<head>\n", with: "<head>\n\(csp)")
    }

    private static func temporaryURL(nextTo url: URL) -> URL {
        url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).pdf.tmp")
    }

    enum PDFExportError: Error {
        case invalidPDFOutput
    }
}

/// A navigation delegate that bridges WKWebView's callback-based load to an
/// async continuation. WKWebView invokes its delegate on the main thread, so
/// the continuation is resumed on the main actor.
@MainActor
private final class PDFNavigationDelegate: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?

    func load(_ html: String, in webView: WKWebView) async throws {
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
