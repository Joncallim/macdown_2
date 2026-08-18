import Foundation

/// Rejects authored Markdown links whose URL scheme would be dangerous when
/// rendered.
///
/// `CMARK_OPT_UNSAFE` preserves raw HTML for fidelity but, in doing so,
/// disables cmark's normal dangerous-link scrub (its "safe" mode). This policy
/// restores that guard for *authored Markdown* links/images without disabling
/// raw HTML: `javascript:`, `vbscript:`, `data:` and `file:` schemes are
/// rejected at composition time, before the URL can reach the HTML output.
///
/// `data:` is rejected on authored links regardless of media type because a
/// self-contained document's own embedded resources are produced by E12's
/// manifest, never copied verbatim from authored link URLs.
public enum ExportURLPolicy {
    /// Schemes cmark's safe mode would scrub but `UNSAFE` mode does not.
    private static let rejectedSchemes: Set<String> = ["javascript", "vbscript", "data", "file"]

    /// Returns `true` when `url` is safe to emit as an authored Markdown link
    /// or image target.
    public static func isSafe(_ url: String) -> Bool {
        guard let scheme = scheme(of: url) else {
            // Relative references have no scheme and are resolved locally.
            return true
        }
        return !rejectedSchemes.contains(scheme)
    }

    /// The lowercase scheme of `url`, or `nil` when the URL has no scheme (it is
    /// relative or a fragment).
    static func scheme(of url: String) -> String? {
        let scalars = Array(url.unicodeScalars)
        guard let colonIndex = scalars.firstIndex(of: ":") else { return nil }

        // A scheme must begin with an ASCII letter (RFC 3986).
        guard let first = scalars.first,
              first.value >= 0x41, first.value <= 0x7A,
              first.value <= 0x5A || first.value >= 0x61 else {
            return nil
        }

        let prefix = scalars[0 ..< colonIndex]
        var name = ""
        for scalar in prefix {
            guard scalar.value < 128,
                  let codePoint = UnicodeScalar(scalar.value) else {
                return nil
            }
            name.append(Character(codePoint))
        }
        return name.lowercased()
    }
}
