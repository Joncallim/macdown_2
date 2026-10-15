import Foundation

/// Markdown workloads for the size-based highlighting fallback (register row
/// H5). Each kind stresses a different part of the editor path; none is a
/// single repeated line, and the Unicode kind makes UTF-8 bytes and UTF-16
/// units differ (CJK is 3 bytes but 1 unit; an emoji is 4 bytes and 2 units).
enum HighlightBudgetFixture: String, CaseIterable, CustomStringConvertible {
    /// Prose paragraphs with occasional inline markup, headings and lists.
    case ordinary
    /// Inline markup every few words (code spans, emphasis, links).
    case inlineDense
    /// Paragraphs that are each one ~6 KB line with inline markup.
    case longLines
    /// CJK and emoji prose with inline markup.
    case unicode
    /// Mostly fenced code blocks with short prose between them.
    case fences

    var description: String {
        rawValue
    }

    /// Generates at least `utf8Bytes` UTF-8 bytes of this workload.
    func markdown(utf8Bytes: Int) -> String {
        var result = ""
        var index = 0
        while result.utf8.count < utf8Bytes {
            result += block(index)
            index += 1
        }
        return result
    }

    private func block(_ index: Int) -> String {
        switch self {
        case .ordinary: Self.ordinaryBlock(index)
        case .inlineDense: Self.inlineDenseBlock(index)
        case .longLines: Self.longLineBlock(index)
        case .unicode: Self.unicodeBlock(index)
        case .fences: Self.fenceBlock(index)
        }
    }

    private static func ordinaryBlock(_ index: Int) -> String {
        let heading = index.isMultiple(of: 5) ? "## Section \(index / 5)\n\n" : ""
        return heading + """
        Paragraph \(index) explains the idea in plain words, the way most notes are written. It runs \
        for a few sentences without much markup, then mentions *one emphasised phrase* and a `value` \
        before it ends with an ordinary full stop.

        - item \(index) one
        - item \(index) two

        """ + "\n"
    }

    private static func inlineDenseBlock(_ index: Int) -> String {
        """
        # Heading \(index) with `code`

        Use `a\(index)`, *b*, **c**, [d](https://example.com/\(index)), `e` and _f_; then `g`, \
        **h**, *i* and [j](#k\(index)) with `l` and **m**.

        - list item one with `inline` and *em*
        - list item two with **strong**

        > a quote with **bold** and `code`

        ```
        fenced code line \(index)
        ```


        """
    }

    private static func longLineBlock(_ index: Int) -> String {
        let sentence = "Long line \(index) keeps going with *emphasis*, `code`, **strong** and plain words. "
        return String(repeating: sentence, count: 6144 / sentence.utf8.count) + "\n\n"
    }

    private static func unicodeBlock(_ index: Int) -> String {
        """
        ## 見出し \(index) 🚀

        これは*強調*と`コード`を含む段落です。日本語の文章が続きます 😀 そして**太字**も、\
        中文的句子也在这里 ✨ [链接](https://example.com/\(index))。

        - 項目 \(index) 👍
        - 項目 二 🎉


        """
    }

    private static func fenceBlock(_ index: Int) -> String {
        var code = "```swift\n"
        for line in 0 ..< 40 {
            code += "let value\(index)_\(line) = compute(\(line), \"text\") // *not* emphasis\n"
        }
        code += "```\n\n"
        return "Block \(index) introduces some *code*:\n\n" + code
    }
}

extension HighlightBudgetFixture {
    /// The three edit locations measured: near the start, the middle and near
    /// the end, each on a composed-character boundary (never inside a
    /// surrogate pair).
    static func editLocations(in text: String) -> [(name: String, location: Int)] {
        let string = text as NSString
        let length = string.length
        func boundary(_ offset: Int) -> Int {
            string.rangeOfComposedCharacterSequence(at: max(0, min(offset, length - 1))).location
        }
        return [("begin", boundary(20)), ("middle", boundary(length / 2)), ("end", boundary(length - 20))]
    }
}
