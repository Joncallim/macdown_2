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
}
