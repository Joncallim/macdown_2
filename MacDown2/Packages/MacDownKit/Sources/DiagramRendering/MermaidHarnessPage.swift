import Diagrams
import Foundation
import WebKit

/// One offscreen, never-displayed page hosting the bundled Mermaid harness
/// (epic-20-implementation.md §10). Owns exactly one `WKWebView`, loaded
/// once and reused across many `render(_:)` calls by its owning pool slot
/// (`MermaidWebRenderer`).
///
/// Security containment, all independently applied (§10 — layered, not any
/// one relied on alone):
/// - `websiteDataStore = .nonPersistent()`: no cookies/storage survive.
/// - `loadFileURL(_:allowingReadAccessTo:)` scoped exactly to the bundled
///   resource directory: the page can read only its own harness files, not
///   the wider file system, and has no network access at all.
/// - A `WKNavigationDelegate` that cancels any navigation whose destination
///   is not inside that same directory — Mermaid's own rendering call never
///   navigates anywhere; this guards against a hypothetical bug or a future
///   Mermaid version doing so.
/// - A `WKUIDelegate` that denies any popup/new-window request.
/// - The harness page's own Content-Security-Policy (`harness.html`)
///   additionally blocks any network `fetch`/`XHR`/`WebSocket`
///   (`connect-src 'none'`) even if executed script attempted one.
/// - Mermaid's own `securityLevel: 'strict'` configuration (`render.js`)
///   disables `click` interaction directives and sanitizes HTML in labels,
///   so the *output* SVG never carries script-bearing content regardless of
///   how a later consumer treats it.
@MainActor
final class MermaidHarnessPage: NSObject, WKNavigationDelegate, WKUIDelegate {
    private let webView: WKWebView
    private let allowedDirectory: URL
    private var loadContinuation: CheckedContinuation<Void, Error>?

    /// `NSObject` does not permit an `async`/`throws` designated
    /// initializer (it would override `NSObject.init()`'s plain,
    /// synchronous signature), so construction is split: this factory
    /// resolves the bundled harness and performs the async page load,
    /// while `init(allowedDirectory:)` stays a normal, synchronous
    /// designated initializer.
    static func make() async throws -> MermaidHarnessPage {
        guard let harnessURL = Bundle.module.url(forResource: "harness", withExtension: "html") else {
            throw MermaidRenderError.rendererUnavailable
        }
        let page = MermaidHarnessPage(allowedDirectory: harnessURL.deletingLastPathComponent())
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

    /// Calls into the harness's `window.__macdownRenderMermaid` and
    /// interprets its plain, JSON-shaped result (`render.js`'s own doc
    /// comment). Uses `callAsyncJavaScript`, which is purpose-built for a
    /// promise-returning body and binds `source` as an argument rather than
    /// interpolating it into evaluated script text — so diagram text
    /// containing quotes, backslashes, or newlines can never break out of a
    /// string literal, because there is no string literal to break out of.
    func render(_ source: String) async throws -> RenderedMermaidDiagram {
        let result = try await webView.callAsyncJavaScript(
            "return await window.__macdownRenderMermaid(source);",
            arguments: ["source": source],
            in: nil,
            contentWorld: .page
        )
        guard let dict = result as? [String: Any], let succeeded = dict["ok"] as? Bool else {
            throw MermaidRenderError.rendererUnavailable
        }
        guard succeeded else {
            let message = (dict["message"] as? String) ?? "unknown error"
            throw MermaidRenderError.invalidSyntax(message)
        }
        guard let svg = dict["svg"] as? String else {
            throw MermaidRenderError.rendererUnavailable
        }
        // A `png` decode failure is intentionally not fatal to the whole
        // render: `svg` (Export's only consumer) is still perfectly valid.
        // Only native Preview display loses its snapshot in that case.
        let pngData = (dict["png"] as? String).flatMap { Data(base64Encoded: $0) }
        let width = (dict["width"] as? NSNumber)?.doubleValue ?? 0
        let height = (dict["height"] as? NSNumber)?.doubleValue ?? 0
        return RenderedMermaidDiagram(svg: svg, pngData: pngData, naturalWidth: width, naturalHeight: height)
    }

    func teardown() {
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.stopLoading()
    }

    // MARK: - WKNavigationDelegate

    func webView(_: WKWebView, didFinish _: WKNavigation!) {
        loadContinuation?.resume()
        loadContinuation = nil
    }

    func webView(_: WKWebView, didFail _: WKNavigation!, withError error: Error) {
        loadContinuation?.resume(throwing: error)
        loadContinuation = nil
    }

    func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: Error) {
        loadContinuation?.resume(throwing: error)
        loadContinuation = nil
    }

    func webView(
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

    func webView(
        _: WKWebView,
        createWebViewWith _: WKWebViewConfiguration,
        for _: WKNavigationAction,
        windowFeatures _: WKWindowFeatures
    ) -> WKWebView? {
        nil
    }
}
