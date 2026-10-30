import Foundation

/// Resolves links clicked in the preview.
///
/// Explicit absolute targets retain their destination. Relative references use the current document base,
/// including a parsed URL that still carries the document's previous base after Save As.
public struct PreviewLinkResolver: Sendable, Equatable {
    public let baseURL: URL?

    public init(baseURL: URL? = nil) {
        self.baseURL = baseURL
    }

    /// Resolves `url` relative to the document base URL.
    ///
    /// Inspect the authored reference rather than its inherited scheme. Retained parsed links may have
    /// an old base; explicitly absolute links must never be retargeted merely because the document moved.
    public func resolve(_ url: URL) -> URL {
        let reference = url.relativeString
        guard let baseURL, URL(string: reference)?.scheme == nil else { return url.absoluteURL }
        return URL(string: reference, relativeTo: baseURL)?.absoluteURL ?? url.absoluteURL
    }

    /// What clicking a resolved Preview link may do. The document is untrusted
    /// (a downloaded README, say) and the app is not sandboxed, so handing every
    /// URL to Launch Services would let `[x](scripts/setup.command)`,
    /// `[x](file:///Applications/Foo.app)` or an `ssh:`/`vnc:`/`x-…:` handler run
    /// something on a click.
    public enum LinkAction: Sendable, Equatable {
        /// Hand to the default handler: web pages and mail.
        case open
        /// Open one of the user's own text documents in MostlyText.
        case openInApp(URL)
        /// Show a local file in Finder without opening or executing it.
        case reveal
        /// Do nothing.
        case ignore
    }

    static let openableDocumentExtensions: Set<String> = ["md", "markdown", "mdown", "mkd", "txt", "text"]

    /// `currentDocument` is the document being previewed: a same-document
    /// `#anchor` link resolves to that file plus a fragment, and must not reopen it.
    public static func action(for url: URL, currentDocument: URL? = nil) -> LinkAction {
        switch url.scheme?.lowercased() {
        case "http", "https", "mailto":
            return .open
        case "file":
            guard openableDocumentExtensions.contains(url.pathExtension.lowercased()) else { return .reveal }
            var target = url
            if var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                components.fragment = nil
                components.query = nil
                target = components.url ?? url
            }
            if let currentDocument,
               target.standardizedFileURL.path == currentDocument.standardizedFileURL.path {
                return .ignore
            }
            return .openInApp(target)
        default:
            return .ignore
        }
    }
}
