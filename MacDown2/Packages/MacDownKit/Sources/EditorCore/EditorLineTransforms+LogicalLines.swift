import Foundation

extension EditorLineTransforms {
    /// The logical lines of `content` with the exact separator that follows each. A separator is an LF or a lone CR
    /// (always one UTF-16 unit); the CR of a CRLF pair stays attached to its line, so existing per-line remapping that
    /// assumes one separator unit between lines keeps working. Unlike `lineSplitSeparator`, a block that mixes
    /// `\r` and `\n` (`a\rb\nc`) is split at BOTH, so no logical line is silently skipped by Indent / Toggle
    /// Comment, and rejoining with the returned separators preserves every original terminator.
    static func logicalLines(of content: String) -> (lines: [String], separators: [String]) {
        let units = Array(content.utf16)
        var lines: [String] = []
        var separators: [String] = []
        var start = 0
        var index = 0
        while index < units.count {
            let unit = units[index]
            let isLoneCR = unit == 0x0D && !(index + 1 < units.count && units[index + 1] == 0x0A)
            if unit == 0x0A || isLoneCR {
                lines.append(String(decoding: units[start ..< index], as: UTF16.self))
                separators.append(unit == 0x0A ? "\n" : "\r")
                start = index + 1
            }
            index += 1
        }
        lines.append(String(decoding: units[start...], as: UTF16.self))
        return (lines, separators)
    }

    static func joinLogicalLines(_ lines: [String], separators: [String]) -> String {
        var result = ""
        for (offset, line) in lines.enumerated() {
            result += line
            if offset < separators.count {
                result += separators[offset]
            }
        }
        return result
    }
}
