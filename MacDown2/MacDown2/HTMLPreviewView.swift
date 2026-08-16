import FileCore
import Preview
import SwiftUI
import UniformTypeIdentifiers
import WebKit

// MARK: - HTML preview host

/// App-owned host for the hardened HTML preview (EPIC-11 Gate 4).
///
/// The v1 policy (`HTMLPreviewPolicy.v1`) is enforced here:
/// - Content JavaScript is disabled at the web-view configuration level and
///   no script bridge exists.
/// - The document loads through the `macdown-preview:` custom scheme, so
///   `file:` URLs never reach the web view. The scheme handler
///   (`PreviewSchemeHandler`) serves the main document and subresources only
///   after `HTMLPreviewResourceScope` approves them against the document's
///   directory — symlink-safe containment, `..` traversal rejected. Every
///   response carries the authoritative CSP header
///   (`HTMLPreviewResponseHeaders`), which no markup can divert; `text/html`
///   payloads are additionally re-hardened with the meta CSP injection as
///   belt-and-braces.
/// - `WKNavigationDelegate` cancels every navigation outside the preview
///   scheme (remote URLs, `javascript:` links, `data:` replacements, meta
///   refreshes) and cancels download-only responses; `WKUIDelegate` denies
///   popups outright.
/// - Reloads are latest-request-wins (`HTMLPreviewReloadGate`), debounced,
///   and fire only for *saved* (clean) document generations — unrelated
///   SwiftUI updates never restart WebKit. A failed main-document load
///   re-arms the gate so the same generation can be retried.
struct HTMLPreviewView: NSViewRepresentable {
    let document: FileCore.FileDocument

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        context.coordinator.makeWebView()
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.preview(document: document, in: webView)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.dispose(webView: webView)
    }

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private static let reloadDelay: Duration = .milliseconds(150)

        private let handler = PreviewSchemeHandler()
        private var gate = HTMLPreviewReloadGate()
        private var reloadTask: Task<Void, Never>?
        private var securityScope: PreviewSecurityScope?
        private var pendingLoadGeneration: UInt?

        func makeWebView() -> WKWebView {
            let configuration = WKWebViewConfiguration()
            // v1 policy: content JavaScript off for every navigation. The
            // deprecated `preferences.javaScriptEnabled` is intentionally not
            // used; `defaultWebpagePreferences` is the macOS 11+ replacement.
            // The value reads from the policy so the two cannot drift.
            configuration.defaultWebpagePreferences.allowsContentJavaScript =
                HTMLPreviewPolicy.v1.allowsContentJavaScript
            // No cookies or storage survive between previews.
            configuration.websiteDataStore = .nonPersistent()
            // Every document resource flows through the validated scheme.
            configuration.setURLSchemeHandler(
                handler,
                forURLScheme: HTMLPreviewNavigationPolicy.previewURLScheme
            )

            let webView = WKWebView(frame: .zero, configuration: configuration)
            webView.navigationDelegate = self
            webView.uiDelegate = self
            return webView
        }

        /// Evaluates the current saved revision and starts a debounced,
        /// generation-gated reload. Called on every SwiftUI update; the gate
        /// guarantees unrelated updates cause zero reloads.
        func preview(document: FileCore.FileDocument, in webView: WKWebView) {
            guard document.state == .clean else {
                reloadTask?.cancel()
                reloadTask = nil
                return
            }
            let generation = document.mutationGeneration
            guard gate.shouldLoad(generation: generation) else { return }

            reloadTask?.cancel()
            let source = document.text
            let baseURL = document.fileURL?.deletingLastPathComponent()
            reloadTask = Task { @MainActor [weak self, weak webView] in
                do {
                    try await Task.sleep(for: Self.reloadDelay)
                } catch {
                    return
                }
                guard let self, let webView, !Task.isCancelled else { return }
                beginLoad(
                    source: source,
                    baseURL: baseURL,
                    generation: generation,
                    in: webView
                )
            }
        }

        func dispose(webView: WKWebView) {
            reloadTask?.cancel()
            reloadTask = nil
            gate.cancelPendingLoad()
            pendingLoadGeneration = nil
            handler.request = nil
            webView.stopLoading()
            securityScope?.stop()
            securityScope = nil
        }

        // MARK: Loads

        private func beginLoad(
            source: String,
            baseURL: URL?,
            generation: UInt,
            in webView: WKWebView
        ) {
            // Balance any prior security scope before opening the new one.
            securityScope?.stop()
            securityScope = nil
            if let baseURL {
                securityScope = PreviewSecurityScope(url: baseURL)
            }

            handler.request = HTMLPreviewRequest(
                source: source,
                baseURL: baseURL,
                policy: .v1
            )
            pendingLoadGeneration = generation

            // The main document loads *through the scheme handler* (not via
            // `loadHTMLString`) so the authoritative CSP response header
            // (`HTMLPreviewResponseHeaders`) covers it. A meta-injected CSP
            // alone can land in dead markup (`<template>`, `<select>`, …) and
            // silently do nothing; a response header cannot be diverted.
            guard let previewURL = URL(string: Self.mainDocumentURLString) else { return }
            webView.load(URLRequest(url: previewURL))
        }

        /// The scheme-handler URL for the main document (host `document`,
        /// empty path); subresource URLs resolve beneath it.
        private static let mainDocumentURLString =
            "\(HTMLPreviewNavigationPolicy.previewURLScheme)://document/"

        private func completeLoad() {
            guard let generation = pendingLoadGeneration else { return }
            pendingLoadGeneration = nil
            gate.loadCompleted(generation: generation)
        }

        // MARK: WKNavigationDelegate

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            // A nil targetFrame means a new-window request (`target="_blank"`,
            // `window.open`): classify it as `.newWindow` so the policy's
            // popup denial applies at the navigation layer too, not only via
            // `createWebViewWith`.
            let target: HTMLPreviewNavigationAction.Target = if let frame = navigationAction.targetFrame {
                frame.isMainFrame ? .mainFrame : .subframe
            } else {
                .newWindow
            }
            let action = HTMLPreviewNavigationAction(
                url: navigationAction.request.url,
                isSameDocument: isSameDocumentNavigation(navigationAction, in: webView),
                target: target
            )
            let decision = HTMLPreviewNavigationPolicy.decision(for: action, policy: .v1)
            decisionHandler(decision == .allow ? .allow : .cancel)
        }

        func webView(
            _: WKWebView,
            decidePolicyFor navigationResponse: WKNavigationResponse,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void
        ) {
            // Download denial is a response-layer decision governed by the
            // active request's policy: anything the preview cannot render
            // inline is cancelled rather than offered to the file system.
            let allowsDownloads = handler.request?.policy.allowsDownloads ?? HTMLPreviewPolicy.v1.allowsDownloads
            if !allowsDownloads, !navigationResponse.canShowMIMEType {
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_: WKWebView, didFinish _: WKNavigation!) {
            completeLoad()
        }

        func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: Error) {
            handleLoadFailure(error)
        }

        func webView(_: WKWebView, didFail _: WKNavigation!, withError error: Error) {
            handleLoadFailure(error)
        }

        /// A failed main-document load re-arms the gate so the same saved
        /// generation can be retried on the next update. Cancelled and
        /// superseded loads are ignored (they are not failures), and only the
        /// main document URL may fail the gate: a subframe failure must never
        /// clear a still-pending main load.
        private func handleLoadFailure(_ error: Error) {
            let nsError = error as NSError
            // -999 (NSURLErrorCancelled, incl. policy cancels) and 102
            // (WebKitErrorFrameLoadInterruptedByPolicyChange, supersede) are
            // not failures of the pending load.
            guard nsError.code != NSURLErrorCancelled, nsError.code != 102 else { return }
            guard let failingURLString = nsError.userInfo[NSURLErrorFailingURLStringErrorKey] as? String,
                  failingURLString == Self.mainDocumentURLString
            else {
                return
            }
            guard let generation = pendingLoadGeneration else { return }
            pendingLoadGeneration = nil
            gate.loadFailed(generation: generation)
        }

        // MARK: WKUIDelegate

        func webView(
            _: WKWebView,
            createWebViewWith _: WKWebViewConfiguration,
            for _: WKNavigationAction,
            windowFeatures _: WKWindowFeatures
        ) -> WKWebView? {
            // v1 policy denies popups outright.
            nil
        }

        // MARK: Helpers

        /// A fragment navigation within the currently loaded preview page.
        private func isSameDocumentNavigation(
            _ action: WKNavigationAction,
            in webView: WKWebView
        ) -> Bool {
            guard let requestURL = action.request.url, let currentURL = webView.url else { return false }
            return withoutFragment(requestURL) == withoutFragment(currentURL)
        }

        private func withoutFragment(_ url: URL) -> String {
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                return url.absoluteString
            }
            components.fragment = nil
            return components.string ?? url.absoluteString
        }
    }
}
