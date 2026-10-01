import Foundation

/// A parsed snippet body. The grammar is deliberately tiny and inert — it can
/// only substitute three fixed tokens and can never run anything:
///
/// - `${selection}` — the text the caret's selection covered (empty for a bare caret)
/// - `${clipboard}` — the plain-text clipboard (empty when there is none)
/// - `$0` — where the caret ends up (first occurrence only; later ones expand to nothing)
/// - `\$` and `\\` — a literal `$` and `\`
///
/// Anything else (`$1`, `${name}`, a lone `$`) is ordinary text. Substitution
/// is a single pass, so a clipboard or selection that itself contains `$0` or
/// `${clipboard}` is inserted verbatim, never re-expanded. Line breaks in the
/// body (`\n`, `\r\n`, `\r`) are re-emitted at expansion time using the target
/// document's own terminator plus the insertion line's indentation.
public struct SnippetTemplate: Sendable, Equatable {
    enum Part: Sendable, Equatable {
        case text(String)
        case newline
        case selection
        case clipboard
        case finalCaret
    }

    /// The expanded text and the UTF-16 offset of the final caret inside it.
    public struct Expansion: Sendable, Equatable {
        public let text: String
        public let caretOffset: Int
    }

    let parts: [Part]

    public init(parsing body: String) {
        var parser = Parser(scalars: Array(body.unicodeScalars))
        parts = parser.run()
    }

    public func expand(selection: String, clipboard: String?, indent: String, lineEnding: String) -> Expansion {
        var output = ""
        var caret: Int?
        for part in parts {
            switch part {
            case let .text(text): output += text
            case .newline: output += lineEnding + indent
            case .selection: output += selection
            case .clipboard: output += clipboard ?? ""
            case .finalCaret: caret = output.utf16.count
            }
        }
        return Expansion(text: output, caretOffset: caret ?? output.utf16.count)
    }
}

private struct Parser {
    let scalars: [Unicode.Scalar]
    var index = 0
    var parts: [SnippetTemplate.Part] = []
    var literal = ""
    var hasFinalCaret = false

    mutating func run() -> [SnippetTemplate.Part] {
        while index < scalars.count {
            step()
        }
        flushLiteral()
        return parts
    }

    private mutating func step() {
        let scalar = scalars[index]
        switch scalar {
        case "\\": escape()
        case "$": dollar()
        case "\r", "\n": newline()
        default:
            literal.unicodeScalars.append(scalar)
            index += 1
        }
    }

    private mutating func escape() {
        if index + 1 < scalars.count, scalars[index + 1] == "$" || scalars[index + 1] == "\\" {
            literal.unicodeScalars.append(scalars[index + 1])
            index += 2
        } else {
            literal.unicodeScalars.append("\\")
            index += 1
        }
    }

    private mutating func dollar() {
        if matches("$0") {
            flushLiteral()
            if !hasFinalCaret {
                parts.append(.finalCaret)
                hasFinalCaret = true
            }
            index += 2
        } else if matches("${selection}") {
            flushLiteral()
            parts.append(.selection)
            index += "${selection}".unicodeScalars.count
        } else if matches("${clipboard}") {
            flushLiteral()
            parts.append(.clipboard)
            index += "${clipboard}".unicodeScalars.count
        } else {
            literal.unicodeScalars.append("$")
            index += 1
        }
    }

    private mutating func newline() {
        flushLiteral()
        parts.append(.newline)
        let isCRLF = scalars[index] == "\r" && index + 1 < scalars.count && scalars[index + 1] == "\n"
        index += isCRLF ? 2 : 1
    }

    private mutating func flushLiteral() {
        guard !literal.isEmpty else { return }
        parts.append(.text(literal))
        literal = ""
    }

    private func matches(_ token: String) -> Bool {
        let expected = Array(token.unicodeScalars)
        guard index + expected.count <= scalars.count else { return false }
        return Array(scalars[index ..< index + expected.count]) == expected
    }
}
