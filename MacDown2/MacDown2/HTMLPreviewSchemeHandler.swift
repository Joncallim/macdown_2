import FileCore
import Preview
import UniformTypeIdentifiers
import WebKit

// MARK: - Scheme handler

/// Serves `macdown-preview://` resources for the current preview request.
///
/// The main document and every subresource (relative image/style/font/media
/// and intra-preview navigations) arrive here. The main document is served
/// from the saved source; subresources are resolved against the approved
/// document directory and validated by `HTMLPreviewResourceScope` —
/// including symlink containment — before any byte is served. Every response
/// carries the CSP header (`HTMLPreviewResponseHeaders`), which governs any
/// document the payload renders as and cannot be diverted by markup;
/// `text/html` payloads are additionally re-hardened with the meta CSP
/// injection.
///
/// Serving is synchronous, so a task either completes or fails before WebKit
/// can stop it. The single mutable `request` slot is swapped only on the main
/// actor at load boundaries; WebKit cancels superseded loads' tasks around
/// the same boundary, so a subresource resolved against a newer request's
/// root is theoretically possible only in that interleaving window (same
/// user's directories, no cross-user exposure).
@MainActor
final class PreviewSchemeHandler: NSObject, WKURLSchemeHandler {
    /// The request currently being rendered; `nil` between loads and after
    /// disposal (nothing is served then).
    var request: HTMLPreviewRequest?

    func webView(_: WKWebView, start task: WKURLSchemeTask) {
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
            task.didFailWithError(PreviewSchemeError.denied)
            return
        }
        guard let request else {
            // Nothing is being previewed (between loads or after disposal).
            task.didFailWithError(PreviewSchemeError.denied)
            return
        }
        if url.path.isEmpty || url.path == "/" {
            serveMainDocument(request: request, url: url, task: task)
            return
        }
        serveSubresource(request: request, url: url, task: task)
    }

    func webView(_: WKWebView, stop _: WKURLSchemeTask) {
        // Serving is synchronous: start(_:) always completes or fails the
        // task before stop can arrive, so there is nothing to cancel.
    }

    /// Serves the main document: the saved source with the belt-and-braces
    /// meta-CSP injection plus the authoritative CSP response header.
    private func serveMainDocument(
        request: HTMLPreviewRequest,
        url: URL,
        task: WKURLSchemeTask
    ) {
        let hardened = PreviewSecurity.hardenedHTMLDocument(from: request.source)
        serve(Data(hardened.utf8), policy: request.policy, url: url, task: task)
    }

    private func serveSubresource(
        request: HTMLPreviewRequest,
        url: URL,
        task: WKURLSchemeTask
    ) {
        guard let rootURL = request.baseURL else {
            // Untitled documents have no approved resource root.
            task.didFailWithError(PreviewSchemeError.denied)
            return
        }
        guard let approved = approvedResourceURL(for: url, rootURL: rootURL),
              let data = try? Data(contentsOf: approved)
        else {
            task.didFailWithError(PreviewSchemeError.denied)
            return
        }

        // Re-harden HTML payloads with the meta CSP; everything else — images,
        // fonts, media — is served raw. Either way the response carries the
        // CSP header, so payloads the meta injection cannot harden (non-UTF-8
        // HTML, SVG, XML) are still governed by the authoritative header.
        let isHTML = UTType(filenameExtension: approved.pathExtension)?.preferredMIMEType == "text/html"
        let responseData: Data = if isHTML {
            // The failable initializer is deliberate: a payload that is not
            // valid UTF-8 cannot be meta-hardened, so it is served raw and
            // the browser applies its own encoding detection — the CSP
            // header still applies.
            if let decoded = String(bytes: data, encoding: .utf8) {
                Data(PreviewSecurity.hardenedHTMLDocument(from: decoded).utf8)
            } else {
                data
            }
        } else {
            data
        }
        serve(responseData, policy: request.policy, url: url, task: task)
    }

    /// Finishes `task` with `data` and the hardening response headers.
    private func serve(
        _ data: Data,
        policy: HTMLPreviewPolicy,
        url: URL,
        task: WKURLSchemeTask
    ) {
        let headers = HTMLPreviewResponseHeaders.hardeningHeaders(for: policy)
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        ) else {
            task.didFailWithError(PreviewSchemeError.denied)
            return
        }
        task.didReceive(response)
        task.didReceive(data)
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
