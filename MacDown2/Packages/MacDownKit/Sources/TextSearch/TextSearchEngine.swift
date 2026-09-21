import Foundation

/// Pure, synchronous, single-buffer search — used directly by
/// current-document find on a bounded buffer, and per-file by
/// `WorkspaceSearchEngine` (folder search) inside its own cancellable
/// off-main task. Never touches AppKit, a window, or a document model.
public enum TextSearchEngine {
    /// Every match of `query` in `text`, honoring `options`. Returns an
    /// empty array for an empty query (never an error — an empty query is
    /// not a malformed one, it simply matches nothing) or when the query
    /// truly does not occur. Throws only for a regex query that fails to
    /// compile.
    public static func matches(
        in text: String,
        query: String,
        options: SearchOptions
    ) throws(SearchQueryError) -> [SearchMatch] {
        guard !query.isEmpty else { return [] }
        if options.isRegex {
            return try regexMatches(in: text, pattern: query, options: options)
        }
        return literalMatches(in: text, query: query, options: options)
    }

    // MARK: - Literal

    private static func literalMatches(in text: String, query: String, options: SearchOptions) -> [SearchMatch] {
        let nsText = text as NSString
        guard nsText.length > 0 else { return [] }
        var compareOptions: NSString.CompareOptions = options.isCaseSensitive ? [] : [.caseInsensitive]
        // `.literal` disables Unicode canonical-equivalence matching (e.g.
        // treating a precomposed "é" and "e" + combining acute as equal) —
        // MacDown 2's other text-fidelity code (FileStore's decode path)
        // never performs canonical normalization either, so search must not
        // quietly do so.
        compareOptions.insert(.literal)

        var results: [SearchMatch] = []
        var searchStart = 0
        while searchStart <= nsText.length {
            let searchRange = NSRange(location: searchStart, length: nsText.length - searchStart)
            let found = nsText.range(of: query, options: compareOptions, range: searchRange)
            guard found.location != NSNotFound else { break }
            if !options.isWholeWord || isWholeWordMatch(found, in: nsText) {
                results.append(SearchMatch(range: found))
            }
            // Advance past the start of this match by at least one UTF-16
            // unit even for a (theoretically impossible, since query is
            // non-empty) zero-length match, so the loop always terminates.
            searchStart = found.location + max(found.length, 1)
        }
        return results
    }

    private static let wordCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))

    private static func isWholeWordMatch(_ range: NSRange, in text: NSString) -> Bool {
        if range.location > 0, let before = scalar(endingAt: range.location, in: text), isWordScalar(before) {
            return false
        }
        let end = range.location + range.length
        if end < text.length, let after = scalar(startingAt: end, in: text), isWordScalar(after) {
            return false
        }
        return true
    }

    private static func isWordScalar(_ scalar: Unicode.Scalar) -> Bool {
        wordCharacters.contains(scalar)
    }

    /// The scalar ending at `index` (the previous character), handling
    /// surrogate halves as one scalar — a local equivalent of
    /// `EditorCore`'s `MarkdownEditingAssistEngine.scalar(before:in:)`,
    /// duplicated deliberately rather than shared: `TextSearch` must not
    /// depend on `EditorCore` (one-directional dependency, see
    /// `planning/epic-22-implementation.md` §5.1).
    private static func scalar(endingAt index: Int, in text: NSString) -> Unicode.Scalar? {
        guard index > 0, index <= text.length else { return nil }
        var start = index - 1
        var length = 1
        let unit = text.character(at: start)
        if unit >= 0xDC00, unit <= 0xDFFF, start > 0 {
            let high = text.character(at: start - 1)
            if high >= 0xD800, high <= 0xDBFF {
                start -= 1
                length = 2
            }
        }
        return leadingScalar(in: text, at: start, length: length)
    }

    private static func scalar(startingAt index: Int, in text: NSString) -> Unicode.Scalar? {
        guard index >= 0, index < text.length else { return nil }
        let unit = text.character(at: index)
        let length = (unit >= 0xD800 && unit <= 0xDBFF && index + 1 < text.length) ? 2 : 1
        return leadingScalar(in: text, at: index, length: length)
    }

    private static func leadingScalar(in text: NSString, at index: Int, length: Int) -> Unicode.Scalar? {
        text.substring(with: NSRange(location: index, length: length)).unicodeScalars.first
    }

    // MARK: - Regex

    private static func regexMatches(
        in text: String,
        pattern: String,
        options: SearchOptions
    ) throws(SearchQueryError) -> [SearchMatch] {
        var regexOptions: NSRegularExpression.Options = []
        if !options.isCaseSensitive {
            regexOptions.insert(.caseInsensitive)
        }
        // Whole-word for regex wraps the user's pattern in word-boundary
        // anchors rather than requiring the user to write `\b` themselves —
        // matching how the "Whole Word" checkbox composes with a literal
        // query.
        let effectivePattern = options.isWholeWord ? "\\b(?:\(pattern))\\b" : pattern

        let regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: effectivePattern, options: regexOptions)
        } catch {
            throw SearchQueryError.invalidRegex(error.localizedDescription)
        }

        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        var results: [SearchMatch] = []
        regex.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
            guard let match else { return }
            results.append(SearchMatch(range: match.range))
        }
        return results
    }
}
