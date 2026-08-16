import Foundation

extension JSONScanner {
    // MARK: Values

    mutating func parseValue() -> ParseResult {
        guard let unit = peek() else {
            return .diagnostic(diagnostic("Expected a JSON value.", at: position))
        }
        switch unit {
        case 0x7B: // {
            return parseObject()
        case 0x5B: // [
            return parseArray()
        case 0x22: // "
            return parseStringValue()
        case 0x74, 0x66, 0x6E: // t, f, n
            return parseLiteral()
        case 0x2D, 0x30 ... 0x39: // - or digit
            return parseNumber()
        default:
            return .diagnostic(diagnostic("Unexpected character while reading a JSON value.", at: position))
        }
    }

    mutating func parseObject() -> ParseResult {
        guard nestingDepth < JSONParser.maxNestingDepth else {
            return .diagnostic(diagnostic(
                "Document exceeds the maximum nesting depth of \(JSONParser.maxNestingDepth).",
                at: position
            ))
        }
        nestingDepth += 1
        defer { nestingDepth -= 1 }
        let start = position
        position += 1 // {
        var members: [JSONObjectMember] = []
        // O(1) duplicate detection; the line of the first definition is
        // kept for the diagnostic message.
        //
        // Keys are compared by exact UTF-16 code units, not Swift String
        // canonical equivalence: RFC 8259 names are sequences of code
        // points, so "é" (U+00E9) and "e\u0301" (U+0065 U+0301) are
        // distinct keys. Merging or rejecting them would change
        // observable document semantics.
        var firstDefinitionLine: [[UInt16]: Int] = [:]
        skipWhitespace()

        if peek() == 0x7D { // }
            position += 1
            return .node(JSONNode(
                value: .object([]),
                sourceRange: start ..< position,
                lineRange: lineRange(from: start, to: position)
            ))
        }

        while true {
            skipWhitespace()
            switch parseObjectMember(firstDefinitionLine: &firstDefinitionLine) {
            case let .member(member):
                members.append(member)
            case let .diagnostic(diagnostic):
                return .diagnostic(diagnostic)
            }

            skipWhitespace()
            guard let unit = peek() else {
                return .diagnostic(diagnostic("Unterminated object: expected ',' or '}'.", at: position))
            }
            if unit == 0x2C { // ,
                position += 1
                continue
            }
            if unit == 0x7D { // }
                position += 1
                return .node(JSONNode(
                    value: .object(members),
                    sourceRange: start ..< position,
                    lineRange: lineRange(from: start, to: position)
                ))
            }
            return .diagnostic(diagnostic("Expected ',' or '}' in object.", at: position))
        }
    }

    /// Parses one `"key": value` member, recording its first-definition line
    /// for duplicate detection.
    private mutating func parseObjectMember(
        firstDefinitionLine: inout [[UInt16]: Int]
    ) -> ObjectMemberResult {
        guard peek() == 0x22 else {
            return .diagnostic(diagnostic("Expected a quoted object key.", at: position))
        }
        let keyResult = parseStringRaw()
        let key: String
        let keyRange: Range<Int>
        switch keyResult {
        case let .decoded(value, range):
            key = value
            keyRange = range
        case let .failed(diagnostic):
            return .diagnostic(diagnostic)
        }

        let keyUnits = Array(key.utf16)
        if let firstLine = firstDefinitionLine[keyUnits] {
            return .diagnostic(diagnostic(
                "Duplicate object key '\(key)' (first defined at line \(firstLine)).",
                at: keyRange.lowerBound
            ))
        }
        firstDefinitionLine[keyUnits] = lineNumber(of: keyRange.lowerBound)

        skipWhitespace()
        guard peek() == 0x3A else { // :
            return .diagnostic(diagnostic("Expected ':' after object key.", at: position))
        }
        position += 1
        skipWhitespace()

        switch parseValue() {
        case let .node(value):
            return .member(JSONObjectMember(key: key, keyRange: keyRange, value: value))
        case let .diagnostic(diagnostic):
            return .diagnostic(diagnostic)
        }
    }

    mutating func parseArray() -> ParseResult {
        guard nestingDepth < JSONParser.maxNestingDepth else {
            return .diagnostic(diagnostic(
                "Document exceeds the maximum nesting depth of \(JSONParser.maxNestingDepth).",
                at: position
            ))
        }
        nestingDepth += 1
        defer { nestingDepth -= 1 }
        let start = position
        position += 1 // [
        var elements: [JSONNode] = []
        skipWhitespace()

        if peek() == 0x5D { // ]
            position += 1
            return .node(JSONNode(
                value: .array([]),
                sourceRange: start ..< position,
                lineRange: lineRange(from: start, to: position)
            ))
        }

        while true {
            skipWhitespace()
            switch parseValue() {
            case let .node(element):
                elements.append(element)
            case let .diagnostic(diagnostic):
                return .diagnostic(diagnostic)
            }

            skipWhitespace()
            guard let unit = peek() else {
                return .diagnostic(diagnostic("Unterminated array: expected ',' or ']'.", at: position))
            }
            if unit == 0x2C { // ,
                position += 1
                continue
            }
            if unit == 0x5D { // ]
                position += 1
                return .node(JSONNode(
                    value: .array(elements),
                    sourceRange: start ..< position,
                    lineRange: lineRange(from: start, to: position)
                ))
            }
            return .diagnostic(diagnostic("Expected ',' or ']' in array.", at: position))
        }
    }

    mutating func parseLiteral() -> ParseResult {
        let start = position
        // Compare units directly — materializing the rest of the document
        // as a String per literal would make parsing quadratic.
        for keyword in ["true", "false", "null"] {
            let keywordUnits = Array(keyword.utf16)
            var matches = true
            for (offset, unit) in keywordUnits.enumerated() where peek(offset) != unit {
                matches = false
                break
            }
            guard matches else { continue }
            position += keywordUnits.count
            return .node(JSONNode(
                value: keyword == "null" ? .null : .boolean(keyword == "true"),
                sourceRange: start ..< position,
                lineRange: lineRange(from: start, to: position)
            ))
        }
        return .diagnostic(diagnostic("Invalid literal: expected 'true', 'false', or 'null'.", at: start))
    }

    // MARK: Numbers

    mutating func parseNumber() -> ParseResult {
        let start = position
        if peek() == 0x2D { // -
            position += 1
        }
        guard parseIntegerPart() else {
            return .diagnostic(diagnostic("Invalid number: expected a digit.", at: position))
        }
        if peek() == 0x2E { // .
            position += 1
            guard parseDigits() else {
                return .diagnostic(diagnostic("Invalid number: expected a digit after '.'.", at: position))
            }
        }
        if let unit = peek(), unit == 0x65 || unit == 0x45 { // e, E
            position += 1
            if let sign = peek(), sign == 0x2B || sign == 0x2D {
                position += 1
            }
            guard parseDigits() else {
                return .diagnostic(diagnostic("Invalid number: expected a digit in exponent.", at: position))
            }
        }
        let raw = String(decoding: units[start ..< position], as: UTF16.self)
        return .node(JSONNode(
            value: .number(raw),
            sourceRange: start ..< position,
            lineRange: lineRange(from: start, to: position)
        ))
    }

    /// Consumes the integer part: a leading `0`, or `1-9` followed by any
    /// digits. Returns `false` without advancing when there is no digit.
    mutating func parseIntegerPart() -> Bool {
        if peek() == 0x30 { // 0
            position += 1
            return true
        }
        guard let unit = peek(), (0x31 ... 0x39).contains(unit) else { return false }
        while let unit = peek(), (0x30 ... 0x39).contains(unit) {
            position += 1
        }
        return true
    }

    /// Consumes one or more digits, returning `false` without advancing when
    /// the next unit is not a digit.
    mutating func parseDigits() -> Bool {
        guard let unit = peek(), (0x30 ... 0x39).contains(unit) else { return false }
        while let unit = peek(), (0x30 ... 0x39).contains(unit) {
            position += 1
        }
        return true
    }
}

/// The outcome of parsing one object member: the member or the diagnostic
/// that stopped the object.
private enum ObjectMemberResult {
    case member(JSONObjectMember)
    case diagnostic(JSONDiagnostic)
}
