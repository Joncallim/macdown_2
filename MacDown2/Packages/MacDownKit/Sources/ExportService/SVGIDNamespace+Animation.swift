import Foundation

extension SVGIDNamespace {
    static func keyframeName(_ prelude: String) -> String? {
        let parts = prelude.split(whereSeparator: \.isWhitespace)
        guard parts.count == 2, parts[0].lowercased() == "@keyframes" else { return nil }
        let name = String(parts[1])
        return validID(name) && !animationKeywords.contains(name.lowercased()) ? name : nil
    }

    static func rewriteAnimation(
        in declaration: String, prefix: String, knownKeyframes: Set<String>?
    ) -> String? {
        guard let colon = declaration.firstIndex(of: ":") else { return declaration }
        let property = declaration[..<colon].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard ["animation", "animation-name", "-webkit-animation", "-webkit-animation-name"].contains(property)
        else { return declaration }
        let namesOnly = property.hasSuffix("animation-name")
        let value = String(declaration[declaration.index(after: colon)...])
        let lower = value.lowercased()
        guard !value.contains("\""), !value.contains("'"),
              !["var(", "calc(", "min(", "max(", "clamp("].contains(where: lower.contains)
        else { return nil }
        let importance = value.firstIndex(of: "!")
        let body = importance.map { String(value[..<$0]) } ?? value
        let suffix = importance.map { String(value[$0...]) } ?? ""
        guard suffix.isEmpty || suffix.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "!important"
        else { return nil }
        var output = String(declaration[...colon])
        var token = ""
        let scalars = Array(body.unicodeScalars)
        for index in scalars.indices {
            let scalar = scalars[index]
            if validID(String(scalar)) {
                token.unicodeScalars.append(scalar)
            } else {
                if scalar == ".", token == "-", index + 1 < scalars.count,
                   scalars[index + 1].value >= 0x30, scalars[index + 1].value <= 0x39 {
                    output += "-."
                    token = ""
                    continue
                }
                guard let rewritten = rewrittenAnimationToken(
                    token, namesOnly: namesOnly, prefix: prefix, knownKeyframes: knownKeyframes
                ) else { return nil }
                output += rewritten
                output.unicodeScalars.append(scalar)
                token = ""
            }
        }
        guard let rewritten = rewrittenAnimationToken(
            token, namesOnly: namesOnly, prefix: prefix, knownKeyframes: knownKeyframes
        ) else { return nil }
        output += rewritten
        return output + suffix
    }

    private static func rewrittenAnimationToken(
        _ token: String, namesOnly: Bool, prefix: String, knownKeyframes: Set<String>?
    ) -> String? {
        guard !token.isEmpty else { return token }
        let lower = token.lowercased()
        if token.first?.isNumber == true ||
            (token.first == "-" && token.dropFirst().first?.isNumber == true) {
            return token
        }
        if namesOnly, ["none", "initial", "inherit", "unset", "revert", "revert-layer"].contains(lower) {
            return token
        }
        if !namesOnly, animationKeywords.contains(lower) {
            return token
        }
        // The first pass inventories declarations; the second admits only
        // names owned by a keyframe in this stylesheet.
        if let knownKeyframes, !knownKeyframes.contains(token) {
            return nil
        }
        return prefix + token
    }

    private static let animationKeywords: Set<String> = [
        "none", "normal", "reverse", "alternate", "alternate-reverse", "forwards", "backwards", "both",
        "running", "paused", "infinite", "linear", "ease", "ease-in", "ease-out", "ease-in-out",
        "step-start", "step-end", "steps", "cubic-bezier", "start", "end", "jump-start", "jump-end",
        "jump-none", "jump-both", "initial", "inherit", "unset", "revert", "revert-layer",
    ]
}
