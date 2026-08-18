import Foundation

/// The single built-in export template.
///
/// macOS 1.0 ships exactly one pure-Swift template; there is no template
/// catalog, no Handlebars dependency, and no custom-template loader. The
/// template variables keep the useful legacy concepts — title, style, content —
/// so migration guidance from old MacDown remains possible, but the layer is a
/// fixed function rather than a pluggable abstraction.
public enum BuiltInExportTemplate {
    /// Renders the complete standalone HTML document shell.
    ///
    /// - Parameters:
    ///   - title: the plain-text document title (HTML-escaped here).
    ///   - headExtras: raw markup emitted first inside `<head>`, before the
    ///     title and stylesheet. The PDF adapter uses it for a
    ///     Content-Security-Policy that must govern the whole document.
    ///   - styleElement: the complete `<style>…</style>` block or
    ///     `<link rel="stylesheet" …>` element for the head.
    ///   - visibleTitle: the heading rendered above the body, when front matter
    ///     supplied a title. `nil` emits no heading.
    ///   - body: the rendered body fragment.
    public static func document(
        title: String,
        visibleTitle: String? = nil,
        headExtras: String = "",
        styleElement: String,
        body: String
    ) -> String {
        let titleTag = title.isEmpty ? "" : "<title>\(HTMLEscaping.escape(title))</title>\n"
        let extras = headExtras.isEmpty ? "" : headExtras + "\n"
        let heading = visibleTitle.map { "<h1>\(HTMLEscaping.escape($0))</h1>\n" } ?? ""

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        \(extras)<meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=yes">
        \(titleTag)\(styleElement)
        </head>
        <body>
        \(heading)\(body)
        </body>
        </html>
        """
    }
}

/// Minimal HTML attribute/text escaping for the few template values E12 owns
/// (title text and generated attribute values). Body and stylesheet bytes are
/// produced by cmark / the bundled stylesheet and are not passed through here.
public enum HTMLEscaping {
    private static let escaped: Set<Character> = ["&", "<", ">", "\"", "'"]

    public static func escape(_ text: String) -> String {
        guard text.contains(where: escaped.contains) else { return text }
        var result = ""
        result.reserveCapacity(text.utf8.count)
        for character in text {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&#39;"
            default: result.append(character)
            }
        }
        return result
    }
}
