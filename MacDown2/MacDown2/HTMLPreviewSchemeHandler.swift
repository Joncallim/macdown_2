import FileCore
import Preview
import WebKit

// MARK: - Scheme handler

/// Serves `macdown-preview://` resources for the current preview request.
///
/// The main document and every subresource (relative image/style/font/media
/// and intra-preview navigations) arrive here. The main document is served
/// from the saved source; subresources still use the legacy path check and
/// separate file reopen. That is not atomic filesystem containment. Every response
/// carries the CSP header (`HTMLPreviewResponseHeaders`), which governs any
/// document the payload renders as and cannot be diverted by markup;
/// `text/html` payloads are additionally re-hardened with the meta CSP
/// injection.
///
/// Reads remain synchronous, but delivery callbacks can reenter stop or
/// request replacement. Each admitted attempt therefore owns a revocable
/// delivery token. This does not establish immutable resource authority:
/// a delayed task can still start against the mutable request's newer root
/// until the explicit directory-grant integration in #121 is complete.
@MainActor
final class PreviewSchemeHandler: NSObject, WKURLSchemeHandler {
    private struct DeliveryAttempt {
        let taskID: ObjectIdentifier
        let webViewID: ObjectIdentifier
        let token = UUID()
    }

    private var attempts: [ObjectIdentifier: DeliveryAttempt] = [:]

    /// The request currently being rendered; `nil` between loads and after
    /// disposal (nothing is served then).
    var request: HTMLPreviewRequest? {
        willSet {
            // Retire consumers before replacement/disposal can reenter WebKit.
            // This revokes delivery, not blocking I/O or resource ownership.
            attempts.removeAll()
        }
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        let taskID = ObjectIdentifier(task)
        guard attempts[taskID] == nil else { return }
        let attempt = DeliveryAttempt(taskID: taskID, webViewID: ObjectIdentifier(webView))
        attempts[taskID] = attempt
        // Validate the authority too: the scheme handler is the containment
        // boundary, so host/userinfo/port abuse must fail closed even though
        // the current path mapping ignores them.
        guard let url = task.request.url,
              url.scheme?.lowercased() == HTMLPreviewNavigationPolicy.previewURLScheme,
              url.host == "document",
              url.user == nil,
              url.password == nil,
              url.port == nil
        else {
            fail(task, attempt: attempt)
            return
        }
        guard let request else {
            // Nothing is being previewed (between loads or after disposal).
            fail(task, attempt: attempt)
            return
        }
        guard isLive(attempt) else { return }
        if url.path.isEmpty || url.path == "/" {
            serveMainDocument(request: request, url: url, task: task, attempt: attempt)
            return
        }
        serveSubresource(request: request, url: url, task: task, attempt: attempt)
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {
        let taskID = ObjectIdentifier(task)
        guard attempts[taskID]?.webViewID == ObjectIdentifier(webView) else { return }
        attempts.removeValue(forKey: taskID)
    }

    private func isLive(_ attempt: DeliveryAttempt) -> Bool {
        attempts[attempt.taskID]?.token == attempt.token
    }

    private func consume(_ attempt: DeliveryAttempt) -> Bool {
        guard isLive(attempt) else { return false }
        attempts.removeValue(forKey: attempt.taskID)
        return true
    }

    private func fail(_ task: WKURLSchemeTask, attempt: DeliveryAttempt) {
        guard consume(attempt) else { return }
        task.didFailWithError(PreviewSchemeError.denied)
    }

    /// Serves the main document: the saved source with the belt-and-braces
    /// meta-CSP injection plus the authoritative CSP response header.
    private func serveMainDocument(
        request: HTMLPreviewRequest,
        url: URL,
        task: WKURLSchemeTask,
        attempt: DeliveryAttempt
    ) {
        let hardened = PreviewSecurity.hardenedHTMLDocument(from: request.source)
        serve(
            Data(hardened.utf8),
            headers: HTMLPreviewResponseHeaders.headers(
                for: request.policy,
                contentType: HTMLPreviewContentType.mainDocument
            ),
            url: url,
            task: task,
            attempt: attempt
        )
    }

    private func serveSubresource(
        request: HTMLPreviewRequest,
        url: URL,
        task: WKURLSchemeTask,
        attempt: DeliveryAttempt
    ) {
        guard let rootURL = request.baseURL else {
            // Untitled documents have no approved resource root.
            fail(task, attempt: attempt)
            return
        }
        guard let approved = approvedResourceURL(for: url, rootURL: rootURL),
              let data = try? Data(contentsOf: approved)
        else {
            fail(task, attempt: attempt)
            return
        }

        // Re-harden HTML payloads with the meta CSP; everything else — images,
        // fonts, media — is served raw. Either way the response carries the
        // CSP header, so payloads the meta injection cannot harden (non-UTF-8
        // HTML, SVG, XML) are still governed by the authoritative header.
        let mimeType = HTMLPreviewContentType.forFileExtension(approved.pathExtension)
        var contentType = mimeType
        let responseData: Data
        if HTMLPreviewContentType.isHTML(approved.pathExtension) {
            // The failable initializer is deliberate: a payload that is not
            // valid UTF-8 cannot be meta-hardened, so it is served raw and
            // the browser applies its own encoding detection — the CSP
            // header still applies.
            if let decoded = String(bytes: data, encoding: .utf8) {
                responseData = Data(PreviewSecurity.hardenedHTMLDocument(from: decoded).utf8)
                contentType = HTMLPreviewContentType.mainDocument
            } else {
                responseData = data
            }
        } else {
            responseData = data
        }
        serve(
            responseData,
            headers: HTMLPreviewResponseHeaders.headers(for: request.policy, contentType: contentType),
            url: url,
            task: task,
            attempt: attempt
        )
    }

    /// Finishes `task` with `data` and the hardening response headers.
    private func serve(
        _ data: Data,
        headers: [String: String],
        url: URL,
        task: WKURLSchemeTask,
        attempt: DeliveryAttempt
    ) {
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        ) else {
            fail(task, attempt: attempt)
            return
        }
        guard isLive(attempt) else { return }
        task.didReceive(response)
        guard isLive(attempt) else { return }
        task.didReceive(data)
        // Terminalize before calling out: a callback may admit another attempt.
        guard consume(attempt) else { return }
        task.didFinish()
    }

    /// Maps a `macdown-preview://document/<relative-path>` URL onto the
    /// approved document directory, decoding path components and rejecting
    /// anything outside it.
    private func approvedResourceURL(for url: URL, rootURL: URL) -> URL? {
        let relativePath = url.path
        guard !relativePath.isEmpty, relativePath != "/" else { return nil }

        var candidate = rootURL
        for component in relativePath.dropFirst().split(separator: "/") where !component.isEmpty {
            candidate = candidate.appendingPathComponent(String(component))
        }
        return HTMLPreviewResourceScope.approvedFileURL(for: candidate, relativeTo: rootURL)
    }
}

private enum PreviewSchemeError: Error {
    case denied
}

// MARK: - Security scope

/// Balances `startAccessingSecurityScopedResource` for the preview's resource
/// root. Non-sandboxed builds report `false` from `startAccessing…` and the
/// matching `stopAccessing…` is a documented no-op, so the wrapper is safe in
/// both configurations; sandboxed builds hold the scope for the lifetime of
/// the previewed revision.
@MainActor
final class PreviewSecurityScope {
    private let url: URL
    private let accessed: Bool

    init?(url: URL) {
        self.url = url
        accessed = url.startAccessingSecurityScopedResource()
    }

    func stop() {
        if accessed {
            url.stopAccessingSecurityScopedResource()
        }
    }
}
