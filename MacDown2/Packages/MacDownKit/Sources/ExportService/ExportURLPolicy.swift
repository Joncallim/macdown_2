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
    ///
    /// The grammar is RFC 3986's — `ALPHA *( ALPHA / DIGIT / "+" / "-" / "." )`
    /// before the first `:` — read in one pass with no intermediate array. Two
    /// details match what a browser does rather than what the RFC says, because
    /// the browser is what will run the link: leading whitespace and control
    /// characters are skipped, and tab/newline/return are ignored inside the
    /// scheme. A URL that a browser would treat as `javascript:` must not be
    /// classed as scheme-less here.
    static func scheme(of url: String) -> String? {
        var name = ""
        var started = false

        for scalar in url.unicodeScalars {
            if scalar == ":" {
                return name.isEmpty ? nil : name.lowercased()
            }
            if isStripped(scalar) {
                // Leading whitespace, and tab/newline/return anywhere in the
                // scheme, are removed by URL parsers before the scheme is read.
                if !started || isIgnoredInScheme(scalar) {
                    continue
                }
                return nil
            }
            guard isSchemeCharacter(scalar, isFirst: !started) else { return nil }
            started = true
            name.unicodeScalars.append(scalar)
        }
        return nil
    }

    /// Whitespace and C0 control characters, which never appear in a URL that a
    /// parser has finished with.
    private static func isStripped(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value <= 0x20
    }

    /// Tab, line feed and carriage return: removed from anywhere in a URL.
    private static func isIgnoredInScheme(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value == 0x09 || scalar.value == 0x0A || scalar.value == 0x0D
    }

    private static func isSchemeCharacter(_ scalar: Unicode.Scalar, isFirst: Bool) -> Bool {
        let isLetter = (scalar.value >= 0x41 && scalar.value <= 0x5A)
            || (scalar.value >= 0x61 && scalar.value <= 0x7A)
        if isFirst {
            return isLetter
        }
        let isDigit = scalar.value >= 0x30 && scalar.value <= 0x39
        return isLetter || isDigit || scalar == "+" || scalar == "-" || scalar == "."
    }
}
