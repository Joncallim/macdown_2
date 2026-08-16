import Foundation

extension JSONScanner {
    // MARK: Strings

    mutating func parseStringValue() -> ParseResult {
        switch parseStringRaw() {
        case let .decoded(value, range):
            .node(JSONNode(
                value: .string(value),
                sourceRange: range,
                lineRange: lineRange(from: range.lowerBound, to: range.upperBound)
            ))
        case let .failed(diagnostic):
            .diagnostic(diagnostic)
        }
    }

    /// Parses a quoted string, returning the decoded value and its UTF-16
    /// range (including quotes).
    mutating func parseStringRaw() -> StringResult {
        let start = position
        position += 1 // "
        var decoded = ""
        decoded.reserveCapacity(16)

        while let unit = peek() {
            switch unit {
            case 0x22: // "
                position += 1
                return .decoded(decoded, range: start ..< position)
            case 0x5C: // backslash
                position += 1
                switch parseEscapedUnit() {
                case let .character(character):
                    decoded.append(character)
                case let .failed(diagnostic):
                    return .failed(diagnostic)
                }
            case 0x00 ... 0x1F:
                return .failed(diagnostic("Unescaped control character in string.", at: position))
            default:
                switch appendUnescapedUnit() {
                case let .character(character):
                    decoded.append(character)
                case let .failed(diagnostic):
                    return .failed(diagnostic)
                }
            }
        }
        return .failed(diagnostic("Unterminated string.", at: start))
    }

    /// Parses one escape sequence (the cursor is on the character after the
    /// backslash): `\"`, `\\`, `\/`, `\b`, `\f`, `\n`, `\r`, `\t`, or `\uXXXX`
    /// (including surrogate pairs).
    private mutating func parseEscapedUnit() -> UnitParseOutcome {
        guard let escaped = peek() else {
            return .failed(diagnostic("Unterminated string: dangling escape.", at: position))
        }
        if let replacement = simpleEscapeReplacements[escaped] {
            position += 1
            return .character(replacement)
        }
        if escaped == 0x75 { // \uXXXX
            position += 1
            guard let scalar = parseUnicodeEscape() else {
                return .failed(diagnostic("Invalid \\u escape.", at: position - 1))
            }
            return .character(String(scalar))
        }
        let raw = String(decoding: [escaped], as: UTF16.self)
        return .failed(diagnostic(
            "Invalid escape sequence '\\\(raw)'.",
            at: position
        ))
    }

    /// Appends the unit at the cursor — a whole scalar, or a surrogate pair —
    /// to the decoded string, advancing the cursor. Returns a diagnostic for
    /// an unpaired surrogate (RFC 8259 requires well-formed Unicode).
    private mutating func appendUnescapedUnit() -> UnitParseOutcome {
        let unit = units[position]
        if (0xD800 ... 0xDBFF).contains(unit) {
            guard position + 1 < units.count,
                  (0xDC00 ... 0xDFFF).contains(units[position + 1])
            else {
                return .failed(diagnostic("Unpaired surrogate in string.", at: position))
            }
            let low = units[position + 1]
            let scalarValue = 0x10000 + ((UInt32(unit) - 0xD800) << 10) + (UInt32(low) - 0xDC00)
            guard let scalar = UnicodeScalar(scalarValue) else {
                return .failed(diagnostic("Unpaired surrogate in string.", at: position))
            }
            position += 2
            return .character(String(scalar))
        }
        if (0xDC00 ... 0xDFFF).contains(unit) {
            return .failed(diagnostic("Unpaired surrogate in string.", at: position))
        }
        position += 1
        return .character(String(decoding: [unit], as: UTF16.self))
    }

    /// Decodes `\uXXXX`, including surrogate pairs. Returns `nil` when the
    /// escape is malformed or an unpaired surrogate.
    mutating func parseUnicodeEscape() -> UnicodeScalar? {
        guard let first = readHex4() else { return nil }
        if (0xD800 ... 0xDBFF).contains(first) {
            // Expect a second \u escape with a low surrogate.
            guard peek() == 0x5C, peek(1) == 0x75 else { return nil }
            position += 2
            guard let second = readHex4() else { return nil }
            guard (0xDC00 ... 0xDFFF).contains(second) else { return nil }
            let scalarValue = 0x10000 + ((UInt32(first) - 0xD800) << 10) + (UInt32(second) - 0xDC00)
            return UnicodeScalar(scalarValue)
        }
        if (0xDC00 ... 0xDFFF).contains(first) {
            return nil
        }
        return UnicodeScalar(first)
    }

    mutating func readHex4() -> UInt16? {
        var value: UInt16 = 0
        for _ in 0 ..< 4 {
            guard let unit = peek(), let digit = hexValue(unit) else { return nil }
            value = value << 4 | UInt16(digit)
            position += 1
        }
        return value
    }
}

/// The outcome of appending one decoded unit: the character to append, or the
/// diagnostic that rejected it.
private enum UnitParseOutcome {
    case character(String)
    case failed(JSONDiagnostic)
}

/// Maps an escaped unit to its decoded character for the non-`\u` escapes.
private let simpleEscapeReplacements: [UInt16: String] = [
    0x22: "\"",
    0x5C: "\\",
    0x2F: "/",
    0x62: "\u{08}",
    0x66: "\u{0C}",
    0x6E: "\n",
    0x72: "\r",
    0x74: "\t",
]

private func hexValue(_ unit: UInt16) -> UInt8? {
    switch unit {
    case 0x30 ... 0x39: UInt8(unit - 0x30)
    case 0x61 ... 0x66: UInt8(unit - 0x61 + 10)
    case 0x41 ... 0x46: UInt8(unit - 0x41 + 10)
    default: nil
    }
}
