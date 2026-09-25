import Foundation

// MARK: - Fenced-code/front-matter classification (EPIC-22 §2.3, §6.12, §7.3, Slice 4b)

/// Bounded, local, synchronous classifier for whether a UTF-16 offset sits
/// inside a fenced code block, YAML front matter, or ordinary prose. Never
/// touches `MarkdownEngine`/`SourceMap` (E10's own "no full parse on the hot
/// path" rule, §2.1) — this is a plain `NSString` scan, closing the E10
/// inherited-debt item §2.3 named.
///
/// See §6.12 for the full design reasoning this type implements, including
/// why a bounded backward scan can only be exact up to a finite cap (it is
/// exact for the overwhelming majority of real documents, which are far
/// smaller than that cap) and why fence-line detection here is a practical,
/// disclosed approximation of CommonMark's own grammar rather than a second
/// Markdown parser.
enum FencedRegionClassifier {
    enum Classification: Equatable {
        case prose
        case frontMatter
        /// The fence's own info string, reduced to its first
        /// whitespace-delimited token and lowercased — a candidate
        /// `LanguageEditingProfileRegistry` key. `nil` for an absent or
        /// empty info string.
        case fencedCode(languageID: String?)
    }

    /// How many lines this scans backward from the caret's own line before
    /// giving up and reporting `.prose` — see §6.12 for why this is a
    /// disclosed, not-unboundedly-correct tradeoff.
    private static let maximumFenceLinesScanned = 20000

    /// How many lines this scans FORWARD from a document's own first line,
    /// looking for a front-matter block's closing delimiter, before giving
    /// up and reporting "no front matter" — much smaller than the fence
    /// scan's own cap, since a real front-matter block is conventionally a
    /// handful of lines, not proportional to document size.
    private static let maximumFrontMatterLinesScanned = 1000

    static func classify(text: NSString, atUTF16Offset offset: Int) -> Classification {
        let caret = min(max(0, offset), text.length)

        if let frontMatterEnd = frontMatterEnd(in: text), caret < frontMatterEnd {
            return .frontMatter
        }

        var currentLineStart = MarkdownEditingAssistEngine.lineStart(of: caret, in: text)
        var fenceCount = 0
        var nearestLanguageID: String?
        var linesScanned = 0

        while currentLineStart > 0, linesScanned < maximumFenceLinesScanned {
            let previousLineStart = MarkdownEditingAssistEngine.lineStart(of: currentLineStart - 1, in: text)
            let previousLineContentEnd = MarkdownEditingAssistEngine.lineContentEnd(of: previousLineStart, in: text)
            if let fence = fenceDelimiter(
                lineStart: previousLineStart,
                lineContentEnd: previousLineContentEnd,
                in: text
            ) {
                fenceCount += 1
                if fenceCount == 1 {
                    nearestLanguageID = fence.languageID
                }
            }
            currentLineStart = previousLineStart
            linesScanned += 1
        }

        guard fenceCount % 2 == 1 else { return .prose }
        return .fencedCode(languageID: nearestLanguageID)
    }

    /// If the line spanning `lineStart..<lineContentEnd` is a fence
    /// delimiter (up to 3 leading spaces, then 3+ of the same backtick or
    /// tilde character), its marker character and derived `languageID`.
    private static func fenceDelimiter(
        lineStart: Int,
        lineContentEnd: Int,
        in text: NSString
    ) -> (character: unichar, languageID: String?)? {
        var index = lineStart
        var leadingSpaces = 0
        while index < lineContentEnd, leadingSpaces < 3,
              MarkdownEditingAssistEngine.character(at: index, in: text) == 0x20 {
            leadingSpaces += 1
            index += 1
        }
        guard index < lineContentEnd else { return nil }
        let marker = MarkdownEditingAssistEngine.character(at: index, in: text)
        guard marker == 0x60 || marker == 0x7E else { return nil } // ` or ~
        var fenceLength = 0
        while index < lineContentEnd, MarkdownEditingAssistEngine.character(at: index, in: text) == marker {
            fenceLength += 1
            index += 1
        }
        guard fenceLength >= 3 else { return nil }

        let infoString = text.substring(with: NSRange(location: index, length: lineContentEnd - index))
            .trimmingCharacters(in: .whitespaces)
        let firstToken = infoString.split(separator: " ").first.map { String($0).lowercased() }
        return (marker, (firstToken?.isEmpty == false) ? firstToken : nil)
    }

    /// The UTF-16 offset at which ordinary content resumes after a
    /// front-matter block, or `nil` if `text` doesn't open with one at all.
    private static func frontMatterEnd(in text: NSString) -> Int? {
        guard text.length > 0 else { return nil }
        let firstLineContentEnd = MarkdownEditingAssistEngine.lineContentEnd(of: 0, in: text)
        guard isExactly(text, range: NSRange(location: 0, length: firstLineContentEnd), matching: "---") else {
            return nil
        }

        var lineStart = firstLineContentEnd + separatorLength(at: firstLineContentEnd, in: text)
        var linesScanned = 0
        while lineStart < text.length, linesScanned < maximumFrontMatterLinesScanned {
            let contentEnd = MarkdownEditingAssistEngine.lineContentEnd(of: lineStart, in: text)
            let lineRange = NSRange(location: lineStart, length: contentEnd - lineStart)
            if isExactly(text, range: lineRange, matching: "---") ||
                isExactly(text, range: lineRange, matching: "...") {
                return contentEnd + separatorLength(at: contentEnd, in: text)
            }
            lineStart = contentEnd + separatorLength(at: contentEnd, in: text)
            linesScanned += 1
        }
        return nil
    }

    private static func isExactly(_ text: NSString, range: NSRange, matching literal: String) -> Bool {
        range.length == literal.utf16.count && text.substring(with: range) == literal
    }

    private static func separatorLength(at contentEnd: Int, in text: NSString) -> Int {
        guard contentEnd < text.length else { return 0 }
        if MarkdownEditingAssistEngine.character(at: contentEnd, in: text) == 0x0D,
           contentEnd + 1 < text.length,
           MarkdownEditingAssistEngine.character(at: contentEnd + 1, in: text) == 0x0A {
            return 2
        }
        return 1
    }
}
