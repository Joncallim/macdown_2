import Foundation

public extension String {
    /// The physical lines of the text, split on CommonMark's three line endings
    /// (`\n`, `\r\n`, a lone `\r`) with the terminators removed. A trailing
    /// terminator yields a final empty line, like `components(separatedBy: "\n")`
    /// does for LF text. Scans UTF-8: `String`'s own `"\r\n"` is a single
    /// grapheme, so Character-level searches for `"\n"` miss it.
    func markdownLines() -> [String] {
        var lines: [String] = []
        var lineStart = utf8.startIndex
        var index = utf8.startIndex
        while index < utf8.endIndex {
            let byte = utf8[index]
            let next = utf8.index(after: index)
            if byte == 0x0A || byte == 0x0D {
                lines.append(String(self[lineStart ..< index]))
                var resume = next
                if byte == 0x0D, resume < utf8.endIndex, utf8[resume] == 0x0A {
                    resume = utf8.index(after: resume)
                }
                lineStart = resume
                index = resume
            } else {
                index = next
            }
        }
        lines.append(String(self[lineStart...]))
        return lines
    }
}

public extension String {
    /// The inner text of a fenced block given its full source: the opening delimiter line is
    /// dropped, and so is the last line IF it is a closing fence (three or more backticks or tildes,
    /// optionally indented or followed by spaces). An unterminated fence — normal while the author is
    /// still typing — keeps its last content line instead of losing it.
    func fencedBlockInnerText() -> String {
        var lines = markdownLines()
        guard !lines.isEmpty else { return "" }
        lines.removeFirst()
        // A trailing line terminator leaves an empty final element that is not content.
        if lines.last?.isEmpty == true {
            lines.removeLast()
        }
        if let last = lines.last, Self.isClosingFenceLine(last) {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }

    private static func isClosingFenceLine(_ line: String) -> Bool {
        // A fence nested in a block quote carries its `>` prefix on the closing line too.
        let trimmed = line.drop { $0 == " " || $0 == "\t" || $0 == ">" }.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3, let first = trimmed.first, first == "`" || first == "~" else { return false }
        return trimmed.allSatisfy { $0 == first }
    }
}
