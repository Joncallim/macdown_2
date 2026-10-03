import Foundation

/// A small, linear HTML tag tokenizer for `DerivedHTMLSanitizer`: quote-aware, and it never backtracks.
enum HTMLTagScanner {
    struct Attribute {
        let name: String
        var value: String?
    }

    struct Tag {
        let name: String
        let isClosing: Bool
        let isSelfClosing: Bool
        let attributes: [Attribute]
        let end: Int
    }

    static func isNameStart(_ scalar: Unicode.Scalar) -> Bool {
        (scalar.value >= 0x41 && scalar.value <= 0x5A) || (scalar.value >= 0x61 && scalar.value <= 0x7A)
            || scalar == "_" || scalar == ":"
    }

    static func isNameCharacter(_ scalar: Unicode.Scalar) -> Bool {
        isNameStart(scalar) || (scalar.value >= 0x30 && scalar.value <= 0x39) || scalar == "-" || scalar == "."
    }

    static func isSpace(_ scalar: Unicode.Scalar) -> Bool {
        scalar == " " || scalar == "\t" || scalar == "\n" || scalar == "\r" || scalar == "\u{0C}"
    }

    /// Parses a start/end tag at `start` (`<`). `nil` when `<` is plain text or the tag never ends.
    static func parseTag(at start: Int, in scalars: [Unicode.Scalar]) -> Tag? {
        var index = start + 1
        let isClosing = index < scalars.count && scalars[index] == "/"
        if isClosing {
            index += 1
        }
        guard index < scalars.count, isNameStart(scalars[index]) else { return nil }
        var name = String.UnicodeScalarView()
        while index < scalars.count, isNameCharacter(scalars[index]) {
            name.append(scalars[index])
            index += 1
        }
        var attributes: [Attribute] = []
        var isSelfClosing = false
        while index < scalars.count {
            let scalar = scalars[index]
            if scalar == ">" {
                return Tag(
                    name: String(name).lowercased(),
                    isClosing: isClosing,
                    isSelfClosing: isSelfClosing,
                    attributes: attributes,
                    end: index + 1
                )
            }
            if scalar == "/" {
                isSelfClosing = true
                index += 1
                continue
            }
            if isSpace(scalar) || !isNameStart(scalar) {
                index += 1 // whitespace or junk between attributes; junk is dropped
                continue
            }
            isSelfClosing = false
            guard let attribute = parseAttribute(at: &index, in: scalars) else { return nil }
            attributes.append(attribute)
        }
        return nil
    }

    /// Parses `name`, `name=value`, `name="value"` or `name='value'`; `nil` when a quote never closes.
    static func parseAttribute(at index: inout Int, in scalars: [Unicode.Scalar]) -> Attribute? {
        var name = String.UnicodeScalarView()
        while index < scalars.count, isNameCharacter(scalars[index]) {
            name.append(scalars[index])
            index += 1
        }
        var probe = index
        while probe < scalars.count, isSpace(scalars[probe]) {
            probe += 1
        }
        guard probe < scalars.count, scalars[probe] == "=" else {
            return Attribute(name: String(name).lowercased(), value: nil)
        }
        probe += 1
        while probe < scalars.count, isSpace(scalars[probe]) {
            probe += 1
        }
        guard probe < scalars.count else { return nil }
        var value = String.UnicodeScalarView()
        let quote = scalars[probe]
        if quote == "\"" || quote == "'" {
            probe += 1
            while probe < scalars.count, scalars[probe] != quote {
                value.append(scalars[probe])
                probe += 1
            }
            guard probe < scalars.count else { return nil }
            probe += 1
        } else {
            while probe < scalars.count, !isSpace(scalars[probe]), scalars[probe] != ">" {
                value.append(scalars[probe])
                probe += 1
            }
        }
        index = probe
        return Attribute(name: String(name).lowercased(), value: String(value))
    }

    static func hasPrefix(_ prefix: String, at start: Int, in scalars: [Unicode.Scalar]) -> Bool {
        let units = Array(prefix.unicodeScalars)
        guard start + units.count <= scalars.count else { return false }
        return zip(units, scalars[start...]).allSatisfy { $0 == $1 }
    }

    /// Copies from `start` through the next `terminator`; `nil` (drop the rest) if there is none.
    static func copyThrough(
        _ terminator: String,
        from start: Int,
        in scalars: [Unicode.Scalar],
        into output: inout String.UnicodeScalarView
    ) -> Int? {
        guard let end = skipPast(terminator, from: start, in: scalars, caseSensitive: true) else { return nil }
        output.append(contentsOf: scalars[start ..< end])
        return end
    }

    /// The index just after the next case-insensitive `marker` (and the `>` closing that tag, for `</script`).
    static func skipPast(
        _ marker: String,
        from start: Int,
        in scalars: [Unicode.Scalar],
        caseSensitive: Bool = false
    ) -> Int? {
        let needle = Array((caseSensitive ? marker : marker.lowercased()).unicodeScalars)
        var index = start
        while index + needle.count <= scalars.count {
            var matches = true
            for offset in 0 ..< needle.count {
                let scalar = scalars[index + offset]
                let folded = caseSensitive ? scalar : Unicode.Scalar(String(scalar).lowercased()) ?? scalar
                if folded != needle[offset] {
                    matches = false
                    break
                }
            }
            if matches {
                var end = index + needle.count
                if !caseSensitive {
                    while end < scalars.count, scalars[end] != ">" {
                        end += 1
                    }
                    end = min(end + 1, scalars.count)
                }
                return end
            }
            index += 1
        }
        return nil
    }

    /// The index after the end of the comment opening at `start`: the first `-->` or `--!>` after the opener, or
    /// the abrupt `<!-->` / `<!--->` forms; `nil` (drop the rest) when it never ends.
    static func commentEnd(from start: Int, in scalars: [Unicode.Scalar]) -> Int? {
        let bodyStart = start + 4
        if hasPrefix(">", at: bodyStart, in: scalars) {
            return bodyStart + 1
        }
        if hasPrefix("->", at: bodyStart, in: scalars) {
            return bodyStart + 2
        }
        var index = bodyStart
        while index + 2 < scalars.count {
            if scalars[index] == "-", scalars[index + 1] == "-" {
                if scalars[index + 2] == ">" {
                    return index + 3
                }
                if scalars[index + 2] == "!", index + 3 < scalars.count, scalars[index + 3] == ">" {
                    return index + 4
                }
            }
            index += 1
        }
        return nil
    }
}
