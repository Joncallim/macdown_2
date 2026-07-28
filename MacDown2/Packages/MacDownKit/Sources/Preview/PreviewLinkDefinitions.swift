import Foundation

/// Extracts CommonMark link reference definitions from the whole document
/// source, so they can be replayed into each independently-parsed preview
/// block.
///
/// A link reference definition (`[label]: destination "title"`) is resolved
/// during parsing and is normally visible to every reference anywhere in the
/// same document. Because each ``PreviewBlock`` is handed to Textual as its
/// own standalone parse, a definition living in one block is invisible to a
/// `[text][label]` reference living in another — the reference renders as
/// literal text instead of a link. Prepending every definition's original
/// line to a block's source before it reaches Textual gives that block's
/// parse the same reference map a whole-document parse would have had.
/// Reference definitions produce no visible output on their own, so this is
/// safe to do unconditionally.
///
/// Known limitations, accepted as proportionate to the common case:
/// - Only single-line definitions are recognized. CommonMark also allows the
///   destination/title to continue onto a following line; that form is rare
///   in practice and is left to degrade to the pre-existing behavior
///   (unresolved reference rendered as literal text).
/// - Extraction is text-only and not fence-aware, so a line that looks like a
///   definition inside a fenced code block would be misidentified. This
///   mirrors the same trade-off already accepted for reference-definition
///   detection versus a full CommonMark parse.
public enum PreviewLinkDefinitions {
    /// Reference definition lines found anywhere in `text`, in document
    /// order, with original formatting preserved.
    ///
    /// Recognizes a line matching: up to three leading spaces (CommonMark's
    /// allowance for a definition to be indented like other block content),
    /// `[label]:`, at least one space or tab, then a destination starting
    /// with a non-whitespace character. Everything after that is accepted
    /// unconstrained (the title, if any).
    ///
    /// Scans a `unichar` buffer directly rather than matching a `Regex` per
    /// line — ~30x faster on a 1 MB document (19.6 ms → 0.64 ms), verified
    /// against the `Regex` version it replaced across empty labels, missing
    /// separators, the 3-vs-4-space indent boundary, tab/mixed separators,
    /// and non-ASCII whitespace immediately after the colon (which must not
    /// count as the start of a destination).
    public static func extract(from text: String) -> [String] {
        let nsText = text as NSString
        let length = nsText.length
        guard length > 0 else { return [] }

        var buffer = [unichar](repeating: 0, count: length)
        nsText.getCharacters(&buffer, range: NSRange(location: 0, length: length))

        var definitions: [String] = []
        var lineStart = 0
        var index = 0

        while index <= length {
            if index == length || buffer[index] == Self.newline {
                let lineEnd = index
                if isDefinitionLine(buffer, from: lineStart, to: lineEnd) {
                    definitions.append(nsText.substring(with: NSRange(
                        location: lineStart,
                        length: lineEnd - lineStart
                    )))
                }
                lineStart = index + 1
            }
            index += 1
        }

        return definitions
    }

    private static let space = unichar(0x20)
    private static let tab = unichar(0x09)
    private static let newline = unichar(0x0A)
    private static let openBracket = unichar(0x5B) // [
    private static let closeBracket = unichar(0x5D) // ]
    private static let colon = unichar(0x3A) // :

    private static func isDefinitionLine(_ buffer: [unichar], from lineStart: Int, to lineEnd: Int) -> Bool {
        var cursor = lineStart

        var spaceCount = 0
        while cursor < lineEnd, buffer[cursor] == space, spaceCount < 3 {
            cursor += 1
            spaceCount += 1
        }

        guard cursor < lineEnd, buffer[cursor] == openBracket else { return false }
        cursor += 1

        // Label: one or more characters that are not ']' (line bounds
        // already exclude '\n').
        let labelStart = cursor
        while cursor < lineEnd, buffer[cursor] != closeBracket {
            cursor += 1
        }
        guard cursor > labelStart, cursor < lineEnd, buffer[cursor] == closeBracket else { return false }
        cursor += 1

        guard cursor < lineEnd, buffer[cursor] == colon else { return false }
        cursor += 1

        let separatorStart = cursor
        while cursor < lineEnd, buffer[cursor] == space || buffer[cursor] == tab {
            cursor += 1
        }
        guard cursor > separatorStart else { return false }

        // The destination must start with a non-whitespace character; the
        // rest of the line is unconstrained.
        guard cursor < lineEnd, isNonWhitespace(buffer[cursor]) else { return false }

        return true
    }

    private static func isNonWhitespace(_ character: unichar) -> Bool {
        guard let scalar = Unicode.Scalar(character) else { return true }
        return !CharacterSet.whitespacesAndNewlines.contains(scalar)
    }
}
