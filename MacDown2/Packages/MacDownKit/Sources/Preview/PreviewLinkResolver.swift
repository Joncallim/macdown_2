import Foundation

/// Resolves links clicked in the preview.
///
/// Absolute URLs are returned unchanged. Relative URLs are resolved against the
/// document's base URL when one is available.
public struct PreviewLinkResolver: Sendable, Equatable {
    public let baseURL: URL?

    public init(baseURL: URL? = nil) {
        self.baseURL = baseURL
    }

    /// Resolves `url` relative to the document base URL.
    ///
    /// Returns `url` unchanged when it is already absolute or when no base URL
    /// is set.
    public func resolve(_ url: URL) -> URL {
        guard url.scheme == nil || url.scheme?.isEmpty == true else {
            return url
        }
        guard let baseURL else { return url }
        return URL(string: url.absoluteString, relativeTo: baseURL)?.absoluteURL ?? url
    }

    /// What clicking a resolved Preview link may do. The document is untrusted
    /// (a downloaded README, say) and the app is not sandboxed, so handing every
    /// URL to Launch Services would let `[x](scripts/setup.command)`,
    /// `[x](file:///Applications/Foo.app)` or an `ssh:`/`vnc:`/`x-…:` handler run
    /// something on a click.
    public enum LinkAction: Sendable, Equatable {
        /// Hand to the default handler: web pages, mail, and the user's own text documents.
        case open
        /// Show a local file in Finder without opening or executing it.
        case reveal
        /// Do nothing.
        case ignore
    }

    static let openableDocumentExtensions: Set<String> = ["md", "markdown", "mdown", "mkd", "txt", "text"]

    public static func action(for url: URL) -> LinkAction {
        switch url.scheme?.lowercased() {
        case "http", "https", "mailto":
            return .open
        case "file":
            let pathExtension = url.pathExtension.lowercased()
            return openableDocumentExtensions.contains(pathExtension) ? .open : .reveal
        default:
            return .ignore
        }
    }
}
