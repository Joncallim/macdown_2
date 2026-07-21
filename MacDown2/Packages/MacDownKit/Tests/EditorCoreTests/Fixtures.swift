import Foundation

/// Deterministic Markdown fixtures for performance tests.
enum Fixtures {
    /// Generates a Markdown string of approximately `targetByteCount` bytes.
    ///
    /// The output mixes paragraphs, headers, lists, and code blocks so the
    /// text system exercises a realistic variety of line lengths and syntax
    /// markers without relying on external files.
    static func markdown(targetByteCount: Int) -> String {
        let line = "The quick brown fox jumps over the lazy dog. "
        let paragraph = String(repeating: line, count: 10) + "\n\n"
        let paragraphCount = max(1, targetByteCount / paragraph.utf8.count)

        var result = ""
        result.reserveCapacity(targetByteCount)

        for index in 0 ..< paragraphCount {
            switch index % 5 {
            case 0:
                result += "# Heading \(index)\n\n"
                result += paragraph
            case 1:
                result += "- List item \(index)-a\n"
                result += "- List item \(index)-b\n"
                result += "- List item \(index)-c\n\n"
            case 2:
                result += "> A blockquote that spans a few words so it has some length.\n\n"
            case 3:
                result += "```\nlet x = \(index)\nlet y = x + 1\n```\n\n"
            default:
                result += paragraph
            }

            if result.utf8.count >= targetByteCount {
                break
            }
        }

        return result
    }
}
