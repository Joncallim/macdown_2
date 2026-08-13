import Foundation

// MARK: - Return / list / task / blockquote continuation

extension MarkdownEditingAssistEngine {
    static func newlineOutcome(
        text: NSString,
        selection: NSRange,
        configuration: EditingAssistConfiguration
    ) -> EditingAssistOutcome {
        guard configuration.continuesMarkdownPrefixes else { return .passthrough }
        guard selection.length == 0 else { return .passthrough }
        let caret = selection.location

        let prefix = linePrefix(before: caret, in: text)

        let hasConstruct = prefix.listMarker != nil || prefix.taskMarker != nil
            || !prefix.blockquotePrefix.isEmpty
            || !prefix.indentation.isEmpty
        guard hasConstruct else { return .passthrough }

        // Range-scoped emptiness scan on the live source. The content range
        // can span the whole document in a pathological single-line file, so
        // it is never materialized as a Swift `String` copy here.
        let contentEnd = lineContentEnd(of: caret, in: text)
        let contentIsEmpty = text.rangeOfCharacter(
            from: .whitespacesAndNewlines.inverted,
            options: [],
            range: NSRange(
                location: prefix.contentRangeInLine.location,
                length: max(0, contentEnd - prefix.contentRangeInLine.location)
            )
        ).location == NSNotFound

        let separator = lineSeparator(ofLineContaining: caret, in: text)

        if contentIsEmpty {
            return terminationOutcome(prefix: prefix, caret: caret, separator: separator, text: text)
        }
        return continuationOutcome(
            prefix: prefix,
            caret: caret,
            separator: separator,
            text: text,
            configuration: configuration
        )
    }

    /// Empty-construct termination: exit one level. Calculates the entire
    /// result first and performs one replacement — never a delete-then-insert
    /// sequence.
    private static func terminationOutcome(
        prefix: MarkdownLinePrefix,
        caret: Int,
        separator: String,
        text: NSString
    ) -> EditingAssistOutcome {
        let nextLinePrefix: String
        if prefix.listMarker != nil || prefix.taskMarker != nil {
            // Remove the list/task marker; keep quote context.
            nextLinePrefix = prefix.indentation + prefix.blockquotePrefix
        } else if !prefix.blockquotePrefix.isEmpty {
            // Exit the quote entirely.
            nextLinePrefix = prefix.indentation
        } else {
            // Whitespace-only line without a list/quote construct: native.
            return .passthrough
        }
        let lineStart = lineStart(of: caret, in: text)
        let range = NSRange(location: lineStart, length: caret - lineStart)
        let replacementText = separator + nextLinePrefix
        return .edit(EditingAssistEdit(
            replacementRange: range,
            replacementString: replacementText,
            resultingSelection: NSRange(location: lineStart + replacementText.utf16.count, length: 0),
            undoActionName: "Continue List"
        ))
    }

    /// Normal continuation. When splitting immediately before an
    /// already-present exact continuation prefix, only the separator is
    /// inserted so the prefix is not duplicated (decided from the original
    /// live text before any mutation).
    private static func continuationOutcome(
        prefix: MarkdownLinePrefix,
        caret: Int,
        separator: String,
        text: NSString,
        configuration: EditingAssistConfiguration
    ) -> EditingAssistOutcome {
        let nextLinePrefix = continuationPrefix(for: prefix, configuration: configuration)
        let replacementText = separator + nextLinePrefix

        // Bounded local search — never a full-document scan.
        let searchLength = min(replacementText.utf16.count, text.length - caret)
        let match = text.range(
            of: replacementText,
            options: [],
            range: NSRange(location: caret, length: max(0, searchLength))
        )
        let replacement: String = if match.location == caret, match.length == replacementText.utf16.count {
            separator
        } else {
            replacementText
        }
        return .edit(EditingAssistEdit(
            replacementRange: NSRange(location: caret, length: 0),
            replacementString: replacement,
            resultingSelection: NSRange(location: caret + replacement.utf16.count, length: 0),
            undoActionName: "Continue List"
        ))
    }

    private static func continuationPrefix(
        for prefix: MarkdownLinePrefix,
        configuration: EditingAssistConfiguration
    ) -> String {
        let outer = prefix.indentation + prefix.blockquotePrefix
        if let marker = prefix.listMarker {
            let markerText: String
            switch marker {
            case let .unordered(character):
                markerText = String(character) + " "
            case let .ordered(rawDigits):
                let digits = configuration.autoIncrementOrderedLists ? incrementedDigits(rawDigits) : rawDigits
                markerText = digits + ". "
            }
            if prefix.taskMarker != nil {
                return outer + markerText + "[ ] "
            }
            return outer + markerText
        }
        if prefix.taskMarker != nil {
            return outer + "[ ] "
        }
        if !prefix.blockquotePrefix.isEmpty {
            return outer
        }
        return prefix.indentation
    }

    /// Safe ordered-number increment: preserves zero-padding width where
    /// possible, repeats the exact digits on overflow/unparseable input.
    private static func incrementedDigits(_ rawDigits: String) -> String {
        guard let value = Int(rawDigits), value < Int.max else { return rawDigits }
        let incremented = String(value + 1)
        if rawDigits.count > incremented.count {
            return String(repeating: "0", count: rawDigits.count - incremented.count) + incremented
        }
        return incremented
    }

    // MARK: - Line prefix parsing

    /// Parses `[indentation][> markers][list marker][task marker]` before the
    /// caret. All offsets are UTF-16.
    static func linePrefix(before caret: Int, in text: NSString) -> MarkdownLinePrefix {
        let start = lineStart(of: caret, in: text)
        let indentation = parseIndentation(from: start, to: caret, in: text)
        var index = start + indentation.utf16.count
        let quote = parseBlockquote(from: &index, to: caret, in: text)
        let listMarker = parseListMarker(from: &index, to: caret, in: text)
        let taskMarker = parseTaskMarker(from: &index, to: caret, in: text)

        return MarkdownLinePrefix(
            indentation: indentation,
            blockquotePrefix: quote,
            listMarker: listMarker,
            taskMarker: taskMarker,
            contentRangeInLine: NSRange(location: index, length: max(0, caret - index))
        )
    }

    private static func parseIndentation(from start: Int, to caret: Int, in text: NSString) -> String {
        var index = start
        while index < caret {
            let character = character(at: index, in: text)
            guard character == 0x20 || character == 0x09 else { break }
            index += 1
        }
        return text.substring(with: NSRange(location: start, length: index - start))
    }

    /// Blockquote markers, preserving each marker's optional space.
    private static func parseBlockquote(from index: inout Int, to caret: Int, in text: NSString) -> String {
        var quote = ""
        while index < caret, character(at: index, in: text) == 0x3E {
            quote.append(">")
            index += 1
            if index < caret, character(at: index, in: text) == 0x20 {
                quote.append(" ")
                index += 1
            }
        }
        return quote
    }

    private static func parseListMarker(from index: inout Int, to caret: Int, in text: NSString) -> ListMarker? {
        guard index < caret else { return nil }
        let marker = character(at: index, in: text)
        if marker == 0x2D || marker == 0x2B || marker == 0x2A {
            if index + 1 < caret, isHorizontalWhitespace(character(at: index + 1, in: text)),
               let scalar = UnicodeScalar(marker)
            // swiftlint:disable:next opening_brace
            {
                index += 2
                return .unordered(Character(scalar))
            }
            return nil
        }
        if !isDigit(marker) {
            return nil
        }
        var digitsEnd = index
        while digitsEnd < caret, isDigit(character(at: digitsEnd, in: text)) {
            digitsEnd += 1
        }
        guard digitsEnd < caret,
              character(at: digitsEnd, in: text) == 0x2E,
              digitsEnd + 1 < caret,
              isHorizontalWhitespace(character(at: digitsEnd + 1, in: text))
        else {
            return nil
        }
        let rawDigits = text.substring(with: NSRange(location: index, length: digitsEnd - index))
        index = digitsEnd + 2
        return .ordered(rawDigits: rawDigits)
    }

    private static func parseTaskMarker(from index: inout Int, to caret: Int, in text: NSString) -> TaskMarker? {
        guard index + 3 < caret, character(at: index, in: text) == 0x5B else { return nil }
        let inner = character(at: index + 1, in: text)
        guard character(at: index + 2, in: text) == 0x5D,
              inner == 0x20 || inner == 0x78 || inner == 0x58,
              isHorizontalWhitespace(character(at: index + 3, in: text))
        else {
            return nil
        }
        index += 4
        return inner == 0x20 ? .unchecked : .checked
    }
}
