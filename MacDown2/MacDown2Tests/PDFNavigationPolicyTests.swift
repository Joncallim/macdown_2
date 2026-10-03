import Foundation
@testable import MacDown2
import Testing
import WebKit

/// PDF export keeps authored raw HTML; a `<meta http-equiv=refresh>` in it was followed to a remote URL (the
/// export called out to the network and could print the remote page), because the print web view allowed every
/// navigation and the CSP only governs subresources.
struct PDFNavigationPolicyTests {
    @Test func onlyTheStringLoadedDocumentMayNavigate() {
        #expect(PDFNavigationPolicy.allows(URL(string: "about:blank")))
        #expect(PDFNavigationPolicy.allows(nil))
    }

    @Test func everyOtherDestinationIsCancelled() {
        for destination in [
            "http://127.0.0.1:18765/leak",
            "https://example.com/",
            "file:///etc/hosts",
            "data:text/html,<p>x</p>",
            "javascript:alert(1)",
            "macdown-preview://document/",
            "about:srcdoc",
        ] {
            #expect(!PDFNavigationPolicy.allows(URL(string: destination)), "\(destination)")
        }
    }
}

/// The policy is only safe if it matches what WebKit actually reports: a string-loaded page must navigate to a URL
/// the policy allows (or the real export would hang), and a meta refresh must be seen as a remote navigation.
@MainActor
struct PDFNavigationPolicyWebKitTests {
    private final class Recorder: NSObject, WKNavigationDelegate {
        var urls: [URL?] = []
        var finished = false

        func webView(
            _: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            urls.append(navigationAction.request.url)
            decisionHandler(PDFNavigationPolicy.allows(navigationAction.request.url) ? .allow : .cancel)
        }

        func webView(_: WKWebView, didFinish _: WKNavigation!) {
            finished = true
        }
    }

    @Test func aStringLoadedPageNavigatesToAnAllowedURLAndAMetaRefreshIsCancelled() async throws {
        let recorder = Recorder()
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = recorder

        let refresh = #"<meta http-equiv="refresh" content="0; url=http://127.0.0.1:9/leak">"#
        webView.loadHTMLString("<html><head>\(refresh)</head><body>x</body></html>", baseURL: nil)
        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        while !recorder.finished, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        try await Task.sleep(for: .milliseconds(500)) // let the refresh fire

        #expect(recorder.finished)
        #expect(recorder.urls.first.flatMap(\.self).map { PDFNavigationPolicy.allows($0) } == true)
        #expect(webView.url?.absoluteString != "http://127.0.0.1:9/leak")
    }
}
