import Foundation

extension SVGIDNamespace {
    static func keyframeName(_ prelude: String) -> String? {
        let parts = prelude.split(whereSeparator: \.isWhitespace)
        guard parts.count == 2, parts[0].lowercased() == "@keyframes" else { return nil }
        let name = String(parts[1])
        return validID(name) && !animationKeywords.contains(name.lowercased()) ? name : nil
    }

    static func rewriteAnimation(in declaration: String, prefix: String) -> String? {
        guard let colon = declaration.firstIndex(of: ":") else { return declaration }
        let property = declaration[..<colon].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard ["animation", "animation-name", "-webkit-animation", "-webkit-animation-name"].contains(property)
        else { return declaration }
        let namesOnly = property.hasSuffix("animation-name")
        let value = declaration[declaration.index(after: colon)...]
        guard !value.contains("\""), !value.contains("'") else { return nil }
        var output = String(declaration[...colon])
        var token = ""
        for scalar in value.unicodeScalars {
            if validID(String(scalar)) {
                token.unicodeScalars.append(scalar)
            } else {
                output += rewrittenAnimationToken(token, namesOnly: namesOnly, prefix: prefix)
                output.unicodeScalars.append(scalar)
                token = ""
            }
        }
        output += rewrittenAnimationToken(token, namesOnly: namesOnly, prefix: prefix)
        return output
    }

    private static func rewrittenAnimationToken(_ token: String, namesOnly: Bool, prefix: String) -> String {
        guard !token.isEmpty else { return token }
        let lower = token.lowercased()
        if token.first?.isNumber == true {
            return token
        }
        if namesOnly, ["none", "initial", "inherit", "unset", "revert", "revert-layer"].contains(lower) {
            return token
        }
        if !namesOnly, animationKeywords.contains(lower) {
            return token
        }
        // Unknown names are occurrence-local too, so an authored page cannot
        // supply a matching keyframe outside this SVG.
        return prefix + token
    }

    private static let animationKeywords: Set<String> = [
        "none", "normal", "reverse", "alternate", "alternate-reverse", "forwards", "backwards", "both",
        "running", "paused", "infinite", "linear", "ease", "ease-in", "ease-out", "ease-in-out",
        "step-start", "step-end", "steps", "cubic-bezier", "start", "end", "jump-start", "jump-end",
        "jump-none", "jump-both", "initial", "inherit", "unset", "revert", "revert-layer",
    ]
}
