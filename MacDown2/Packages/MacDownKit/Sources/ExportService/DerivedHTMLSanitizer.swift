import Foundation

/// Removes active content from HTML fragments contributed by renderers before they are
/// spliced into an export.
///
/// Diagram renderers (Graphviz, D2, Mermaid) turn author-controlled text into SVG, and a
/// diagram link such as `URL="javascript:…"` survives as `xlink:href`/`href`. Contributed
/// HTML bypasses `ExportURLPolicy`, which only sees authored Markdown links, so this applies
/// the same scheme rules plus the usual script/handler/embed removal. Typeset math images
/// (`data:image/png;base64,…` in `src`) are unaffected.
enum DerivedHTMLSanitizer {
    private static func regex(_ pattern: String) -> NSRegularExpression {
        // Patterns are literals in this file; a failure here is a programming error.
        guard let compiled = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { preconditionFailure("invalid sanitizer pattern \(pattern)") }
        return compiled
    }

    private static let blockedElements: Set<String> = ["script", "iframe", "object", "embed"]
    private static let urlAttributes: Set<String> = ["href", "xlink:href", "src", "action", "formaction"]
    private static let animationElements: Set<String> = ["set", "animate", "animatetransform", "animatemotion"]

    /// A single linear pass over the markup: text between tags is copied untouched, and every tag is
    /// re-emitted from its parsed name and attributes, so nothing outside a tag is ever rewritten and the
    /// output cannot re-form a blocked tag (`<scr<iframe>ipt>`) — it is its own fixed point. An unterminated
    /// tag or quoted value fails closed: the remainder is dropped.
    static func sanitized(_ html: String) -> String {
        guard html.contains("<") else { return html }
        let scalars = Array(html.unicodeScalars)
        var output = String.UnicodeScalarView()
        var index = 0
        while index < scalars.count {
            guard scalars[index] == "<" else {
                output.append(scalars[index])
                index += 1
                continue
            }
            guard let next = consumeMarkup(at: index, in: scalars, into: &output) else { break }
            index = next
        }
        return String(output)
    }

    /// Handles the markup construct starting at `start`; returns the index after it, or `nil` to drop the rest.
    private static func consumeMarkup(
        at start: Int,
        in scalars: [Unicode.Scalar],
        into output: inout String.UnicodeScalarView
    ) -> Int? {
        if HTMLTagScanner.hasPrefix("<!--", at: start, in: scalars) {
            return HTMLTagScanner.copyThrough("-->", from: start, in: scalars, into: &output)
        }
        if HTMLTagScanner.hasPrefix("<![CDATA[", at: start, in: scalars) {
            return HTMLTagScanner.copyThrough("]]>", from: start, in: scalars, into: &output)
        }
        guard let tag = HTMLTagScanner.parseTag(at: start, in: scalars) else {
            let nextIndex = start + 1
            guard nextIndex < scalars.count else {
                output.append(contentsOf: "&lt;".unicodeScalars)
                return nextIndex
            }
            let following = scalars[nextIndex]
            if following == "!" || following == "?" { // doctype, XML declaration
                return HTMLTagScanner.copyThrough(">", from: start, in: scalars, into: &output)
            }
            if following == "/" { // `</` + non-letter is a bogus comment: dropped
                return HTMLTagScanner.skipPast(">", from: start, in: scalars, caseSensitive: true)
            }
            if HTMLTagScanner.isNameStart(following) {
                return nil
            } // unterminated tag: fail closed
            // Plain text such as `a < b`. Escaped, so that dropping a neighbouring tag can never leave this
            // `<` adjacent to following characters that would re-form a tag.
            output.append(contentsOf: "&lt;".unicodeScalars)
            return nextIndex
        }
        var next = tag.end
        if blockedElements.contains(tag.name) {
            if tag.name == "script", !tag.isClosing {
                next = HTMLTagScanner.skipPast("</script", from: tag.end, in: scalars) ?? scalars.count
            }
            return next
        }
        if animationElements.contains(tag.name),
           tag.attributes
           .contains(where: { $0.name == "attributename" && $0.value?.lowercased().contains("href") == true }) {
            return next
        }
        output.append(contentsOf: render(tag).unicodeScalars)
        return next
    }

    private static func render(_ tag: HTMLTagScanner.Tag) -> String {
        var result = tag.isClosing ? "</\(tag.name)" : "<\(tag.name)"
        if !tag.isClosing {
            for attribute in tag.attributes {
                if attribute.name.hasPrefix("on") {
                    continue
                }
                guard var value = attribute.value else {
                    result += " \(attribute.name)"
                    continue
                }
                if urlAttributes.contains(attribute.name), !isSafe(
                    decodingEntities(in: value),
                    attribute: attribute.name
                ) {
                    value = "#"
                }
                result += " \(attribute.name)=\"\(value.replacingOccurrences(of: "\"", with: "&quot;"))\""
            }
        }
        if tag.isSelfClosing, !tag.isClosing {
            result += " /"
        }
        return result + ">"
    }

    private static let embeddedImage = regex(#"^\s*data:image/(png|jpe?g|gif|webp);base64,[A-Za-z0-9+/=\s]*$"#)

    private static func isSafe(_ url: String, attribute: String) -> Bool {
        if attribute.lowercased() == "src",
           embeddedImage.firstMatch(in: url, range: NSRange(location: 0, length: (url as NSString).length)) != nil {
            return true
        }
        return ExportURLPolicy.isSafe(url)
    }

    private struct Match {
        let whole: String
        private let result: NSTextCheckingResult
        private let source: NSString

        init(_ result: NSTextCheckingResult, in source: NSString) {
            self.result = result
            self.source = source
            whole = source.substring(with: result.range)
        }

        func group(_ index: Int) -> String? {
            let range = result.range(at: index)
            return range.location == NSNotFound ? nil : source.substring(with: range)
        }
    }

    private static func replacing(
        _ expression: NSRegularExpression,
        in text: String,
        with transform: (Match) -> String
    ) -> String {
        let source = text as NSString
        var output = ""
        var cursor = 0
        for result in expression.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            output += source.substring(with: NSRange(location: cursor, length: result.range.location - cursor))
            output += transform(Match(result, in: source))
            cursor = result.range.location + result.range.length
        }
        return output + source.substring(from: cursor)
    }

    private static let namedEntities = [
        "&colon;": ":", "&Tab;": "\t", "&NewLine;": "\n", "&amp;": "&", "&lpar;": "(", "&rpar;": ")",
    ]
    private static let numericEntity = regex(#"&#(x[0-9a-f]+|[0-9]+);?"#)

    /// What a browser would read after resolving character references in an attribute.
    private static func decodingEntities(in value: String) -> String {
        guard value.contains("&") else { return value }
        var decoded = replacing(numericEntity, in: value) { match in
            let digits = match.group(1) ?? ""
            let code = digits.lowercased().hasPrefix("x")
                ? UInt32(digits.dropFirst(), radix: 16)
                : UInt32(digits)
            return code.flatMap(Unicode.Scalar.init).map { String(Character($0)) } ?? match.whole
        }
        for (entity, replacement) in namedEntities {
            decoded = decoded.replacingOccurrences(of: entity, with: replacement)
        }
        return decoded
    }
}
