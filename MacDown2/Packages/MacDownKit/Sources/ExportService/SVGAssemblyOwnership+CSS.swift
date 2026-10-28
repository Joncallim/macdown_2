import Foundation
import SwiftSoup

extension SVGAssemblyOwnership {
    struct Definitions {
        let keyframes: Set<String>
        let fontFamilies: Set<String>
    }

    static func definitions(in elements: [Element]) -> Definitions? {
        var keyframes: Set<String> = []
        var families: Set<String> = []
        for element in elements where element.tagNameNormal() == "style" {
            guard let css = withoutComments(element.data()), !css.contains("\\"), !css.contains("&")
            else { return nil }
            let keyframeTokens = matches(keyframeToken, in: css)
            let keyframeRules = matches(keyframeRule, in: css)
            guard keyframeTokens.count == keyframeRules.count else { return nil }
            for match in keyframeRules {
                guard let name = capture(1, from: match, in: css) else { return nil }
                keyframes.insert(name.lowercased())
            }

            let faceTokens = matches(fontFaceToken, in: css)
            let faceRules = matches(fontFaceRule, in: css)
            guard faceTokens.count == faceRules.count else { return nil }
            for match in faceRules {
                guard let body = capture(1, from: match, in: css),
                      let familyMatch = matches(fontFamily, in: body).only,
                      let name = capture(1, from: familyMatch, in: body)
                      ?? capture(2, from: familyMatch, in: body),
                      SVGIDNamespace.validID(name) else { return nil }
                families.insert(name.lowercased())
            }
        }
        return Definitions(keyframes: keyframes, fontFamilies: families)
    }

    private static func withoutComments(_ css: String) -> String? {
        let scalars = Array(css.unicodeScalars)
        var output = ""
        var cursor = 0
        var quote: Unicode.Scalar?
        while cursor < scalars.count {
            if let current = quote {
                output.unicodeScalars.append(scalars[cursor])
                // CSS escapes are rejected by the caller, so quote termination
                // is unambiguous after comment stripping.
                if scalars[cursor] == current {
                    quote = nil
                }
                cursor += 1
                continue
            }
            if scalars[cursor] == "\"" || scalars[cursor] == "'" {
                quote = scalars[cursor]
                output.unicodeScalars.append(scalars[cursor])
                cursor += 1
                continue
            }
            if cursor + 1 < scalars.count, scalars[cursor] == "/", scalars[cursor + 1] == "*" {
                guard scalars.count >= cursor + 4,
                      let end = (cursor + 2 ..< scalars.count - 1).first(where: {
                          scalars[$0] == "*" && scalars[$0 + 1] == "/"
                      }) else { return nil }
                output += " "
                cursor = end + 2
                continue
            }
            output.unicodeScalars.append(scalars[cursor])
            cursor += 1
        }
        return quote == nil ? output : nil
    }

    private static func matches(_ expression: NSRegularExpression, in text: String) -> [NSTextCheckingResult] {
        expression.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
    }

    private static func capture(_ index: Int, from match: NSTextCheckingResult, in text: String) -> String? {
        let range = match.range(at: index)
        return range.location == NSNotFound ? nil : (text as NSString).substring(with: range)
    }

    private static func regex(_ pattern: String) -> NSRegularExpression {
        guard let result = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        else { preconditionFailure("invalid fixed CSS definition pattern") }
        return result
    }

    private static let keyframeToken = regex(#"@(?:-[a-z]+-)?keyframes\b"#)
    private static let keyframeRule = regex(#"@(?:-[a-z]+-)?keyframes\s+([A-Za-z0-9_-]+)\s*\{"#)
    private static let fontFaceToken = regex(#"@font-face\b"#)
    private static let fontFaceRule = regex(#"@font-face\s*\{([^{}]*)\}"#)
    private static let fontFamily =
        regex(#"(?:^|;)\s*font-family\s*:\s*(?:["']([A-Za-z0-9_-]+)["']|([A-Za-z0-9_-]+))\s*(?:;|$)"#)
}

private extension Array {
    var only: Element? {
        count == 1 ? first : nil
    }
}
