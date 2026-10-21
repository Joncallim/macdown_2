import Foundation
import WebKit

/// Only the scalar values D2 and Graphviz consume cross the page callback
/// boundary. WebKit's raw bridged `Any` remains on the main actor.
public struct DiagramHarnessResult: Sendable {
    public let succeeded: Bool
    public let message: String?
    public let svg: String?
    public let width: Double
    public let height: Double

    init?(webKitValue: Any) {
        guard let values = webKitValue as? [String: Any],
              let succeeded = values["ok"] as? Bool
        else { return nil }
        self.succeeded = succeeded
        message = values["message"] as? String
        svg = values["svg"] as? String
        width = (values["width"] as? NSNumber)?.doubleValue ?? 0
        height = (values["height"] as? NSNumber)?.doubleValue ?? 0
    }
}

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
    private var evaluations: [UUID: CheckedContinuation<DiagramHarnessResult, any Error>] = [:]

    /// App-owned callbacks still awaiting a WebKit result; kept internal for
    /// lifecycle diagnostics and deterministic teardown tests.
    var pendingEvaluationCount: Int {
        evaluations.count
    }

    /// WebKit's content process behind this page died (memory pressure, a crash in a huge diagram). Every
    /// later evaluation would fail, so the pool replaces a terminated page instead of reusing it.
    public private(set) var isTerminated = false

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
        do {
            try await page.load(harnessURL: harnessURL)
            return page
        } catch {
            page.teardown()
            throw error
        }
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
        try Task.checkCancellation()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                guard !isTerminated else {
                    continuation.resume(throwing: DiagramPoolError.pageUnavailable)
                    return
                }
                loadContinuation = continuation
                webView.loadFileURL(harnessURL, allowingReadAccessTo: allowedDirectory)
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.teardown() }
        }
    }

    /// Evaluates `functionBody` (a `callAsyncJavaScript` body) with
    /// `arguments` bound directly — never string-interpolated — via
    /// WebKit's own argument-binding mechanism, matching
    /// `MermaidHarnessPage.render`'s exact pattern. Validates the shared
    /// result fields on the main actor before completing the continuation;
    /// each language still interprets success and syntax failures itself.
    public func evaluate(_ functionBody: String, arguments: [String: Any]) async throws -> DiagramHarnessResult {
        try Task.checkCancellation()
        guard !isTerminated else { throw DiagramPoolError.pageUnavailable }
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard !isTerminated else {
                    continuation.resume(throwing: DiagramPoolError.pageUnavailable)
                    return
                }
                evaluations[id] = continuation
                webView.callAsyncJavaScript(
                    functionBody,
                    arguments: arguments,
                    in: nil,
                    in: .page
                ) { [weak self] result in
                    self?.finishEvaluation(id, with: result.flatMap { value in
                        guard let parsed = DiagramHarnessResult(webKitValue: value) else {
                            return .failure(DiagramPoolError.pageUnavailable)
                        }
                        return .success(parsed)
                    })
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.finishEvaluation(id, with: .failure(CancellationError()))
            }
        }
    }

    public func teardown() {
        isTerminated = true
        finishLoad(with: .failure(DiagramPoolError.pageUnavailable))
        let pending = evaluations
        evaluations.removeAll()
        for continuation in pending.values {
            continuation.resume(throwing: DiagramPoolError.pageUnavailable)
        }
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.stopLoading()
    }

    // MARK: - WKNavigationDelegate

    public func webView(_: WKWebView, didFinish _: WKNavigation!) {
        finishLoad(with: .success(()))
    }

    public func webViewWebContentProcessDidTerminate(_: WKWebView) {
        isTerminated = true
        finishLoad(with: .failure(DiagramPoolError.pageUnavailable))
        let pending = evaluations
        evaluations.removeAll()
        for continuation in pending.values {
            continuation.resume(throwing: DiagramPoolError.pageUnavailable)
        }
    }

    public func webView(_: WKWebView, didFail _: WKNavigation!, withError error: Error) {
        finishLoad(with: .failure(error))
    }

    public func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: Error) {
        finishLoad(with: .failure(error))
    }

    private func finishLoad(with result: Result<Void, any Error>) {
        guard let continuation = loadContinuation else { return }
        loadContinuation = nil
        continuation.resume(with: result)
    }

    private func finishEvaluation(_ id: UUID, with result: Result<DiagramHarnessResult, any Error>) {
        guard let continuation = evaluations.removeValue(forKey: id) else { return }
        continuation.resume(with: result)
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
