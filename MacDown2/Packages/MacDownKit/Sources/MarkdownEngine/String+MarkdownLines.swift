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
