import Foundation
import WebKit

/// One offscreen, never-displayed page hosting a bundled JS harness,
/// generalized from `MermaidHarnessPage` (epic-20-implementation.md §10)
/// to be renderer-agnostic — this type owns the pool/page lifecycle and
/// security containment; it does not know what JS API a particular
/// diagram language exposes, only how to safely load a harness resource
/// directory and evaluate script against it (epic-21-implementation.md
/// §3.1).
///
/// Security containment, identical to `MermaidHarnessPage`'s own (layered,
/// not any one relied on alone):
/// - `websiteDataStore = .nonPersistent()`: no cookies/storage survive.
/// - `loadFileURL(_:allowingReadAccessTo:)` scoped exactly to the
///   bundled resource directory: no network access at all, not merely
///   unused.
/// - A `WKNavigationDelegate` that cancels any navigation whose
///   destination is not inside that same directory.
/// - A `WKUIDelegate` that denies any popup/new-window request.
/// - The harness page's own Content-Security-Policy (each language's own
///   harness HTML) additionally blocks network `fetch`/`XHR`/`WebSocket`.
@MainActor
public final class DiagramHarnessPage: NSObject, WKNavigationDelegate, WKUIDelegate {
    private let webView: WKWebView
    private let allowedDirectory: URL
    private var loadContinuation: CheckedContinuation<Void, Error>?

    /// `NSObject` does not permit an `async`/`throws` designated
    /// initializer, so construction is split exactly like
    /// `MermaidHarnessPage`'s own: this factory resolves the bundled
    /// harness and performs the async page load, while
    /// `init(allowedDirectory:)` stays a normal, synchronous designated
    /// initializer.
    public static func make(harnessResourceName: String, bundle: Bundle) async throws -> DiagramHarnessPage {
        guard let harnessURL = bundle.url(forResource: harnessResourceName, withExtension: "html") else {
            throw DiagramPoolError.pageUnavailable
        }
        let page = DiagramHarnessPage(allowedDirectory: harnessURL.deletingLastPathComponent())
        try await page.load(harnessURL: harnessURL)
        return page
    }

    private init(allowedDirectory: URL) {
        self.allowedDirectory = allowedDirectory

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        let pagePreferences = WKWebpagePreferences()
        pagePreferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = pagePreferences

        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
    }

    private func load(harnessURL: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            loadContinuation = continuation
            webView.loadFileURL(harnessURL, allowingReadAccessTo: allowedDirectory)
        }
    }

    /// Evaluates `functionBody` (a `callAsyncJavaScript` body) with
    /// `arguments` bound directly — never string-interpolated — via
    /// WebKit's own argument-binding mechanism, matching
    /// `MermaidHarnessPage.render`'s exact pattern. Returns the raw
    /// bridged result; interpreting its shape is the caller's own
    /// language-specific concern.
    public func evaluate(_ functionBody: String, arguments: [String: Any]) async throws -> Any? {
        try await webView.callAsyncJavaScript(functionBody, arguments: arguments, in: nil, contentWorld: .page)
    }

    public func teardown() {
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.stopLoading()
    }

    // MARK: - WKNavigationDelegate

    public func webView(_: WKWebView, didFinish _: WKNavigation!) {
        loadContinuation?.resume()
        loadContinuation = nil
    }

    public func webView(_: WKWebView, didFail _: WKNavigation!, withError error: Error) {
        loadContinuation?.resume(throwing: error)
        loadContinuation = nil
    }

    public func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: Error) {
        loadContinuation?.resume(throwing: error)
        loadContinuation = nil
    }

    public func webView(
        _: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url, url.isFileURL, url.path.hasPrefix(allowedDirectory.path) else {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    // MARK: - WKUIDelegate

    public func webView(
        _: WKWebView,
        createWebViewWith _: WKWebViewConfiguration,
        for _: WKNavigationAction,
        windowFeatures _: WKWindowFeatures
    ) -> WKWebView? {
        nil
    }
}
