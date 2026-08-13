import Foundation

// MARK: - Tab / Shift-Tab indentation

extension MarkdownEditingAssistEngine {
    static func tabOutcome(
        text: NSString,
        selection: NSRange,
        configuration: EditingAssistConfiguration,
        shift: Bool
    ) -> EditingAssistOutcome {
        let width = configuration.indentationWidth

        if shift {
            if selection.length > 0 {
                return unindentSelectedLines(text: text, selection: selection, width: width)
            }
            return collapsedUnindent(text: text, caret: selection.location, width: width)
        }

        guard configuration.convertsTabsToSpaces else { return .passthrough }
        if selection.length > 0 {
            return indentSelectedLines(text: text, selection: selection, width: width)
        }

        // Collapsed Tab: spaces to the next indentation stop.
        let caret = selection.location
        let start = lineStart(of: caret, in: text)
        let column = caret - start
        let spaces = width - (column % width)
        let padding = String(repeating: " ", count: spaces)
        return .edit(EditingAssistEdit(
            replacementRange: NSRange(location: caret, length: 0),
            replacementString: padding,
            resultingSelection: NSRange(location: caret + spaces, length: 0),
            undoActionName: "Indent"
        ))
    }

    private static func indentSelectedLines(text: NSString, selection: NSRange, width: Int) -> EditingAssistOutcome {
        transformSelectedLines(text: text, selection: selection, undoActionName: "Indent") { lines in
            var deltas: [Int] = []
            let processed = lines.map { line in
                deltas.append(width)
                return String(repeating: " ", count: width) + line
            }
            return (processed, deltas)
        }
    }

    private static func unindentSelectedLines(text: NSString, selection: NSRange, width: Int) -> EditingAssistOutcome {
        transformSelectedLines(text: text, selection: selection, undoActionName: "Unindent") { lines in
            var deltas: [Int] = []
            let processed = lines.map { line in
                if line.hasPrefix("\t") {
                    deltas.append(-1)
                    return String(line.dropFirst())
                }
                let leadingSpaces = line.prefix { $0 == " " }.count
                let remove = min(leadingSpaces, width)
                deltas.append(-remove)
                return String(line.dropFirst(remove))
            }
            return (processed, deltas)
        }
    }

    /// Splits the selected logical line range into real lines, applies a
    /// per-line transform producing per-line UTF-16 deltas, and replaces the
    /// whole range once with a remapped selection.
    static func transformSelectedLines(
        text: NSString,
        selection: NSRange,
        undoActionName: String,
        transform: ([String]) -> (lines: [String], deltas: [Int])
    ) -> EditingAssistOutcome {
        let range = selectedLineRange(text: text, selection: selection)
        let content = text.substring(with: range)
        let pieces = content.components(separatedBy: "\n")
        let hasSyntheticTrailing = content.hasSuffix("\n")
        let realCount = pieces.count - (hasSyntheticTrailing ? 1 : 0)
        let realLines = Array(pieces.prefix(realCount))

        let (newLines, deltas) = transform(realLines)
        var newPieces = newLines
        if hasSyntheticTrailing {
            newPieces.append("")
        }
        let newContent = newPieces.joined(separator: "\n")

        let resultingSelection = remappedSelection(
            original: selection,
            rangeLocation: range.location,
            lineLengths: realLines.map(\.utf16.count),
            deltas: deltas,
            newLength: newContent.utf16.count
        )
        return .edit(EditingAssistEdit(
            replacementRange: range,
            replacementString: newContent,
            resultingSelection: resultingSelection,
            undoActionName: undoActionName
        ))
    }

    private static func collapsedUnindent(text: NSString, caret: Int, width: Int) -> EditingAssistOutcome {
        let start = lineStart(of: caret, in: text)
        guard caret > start else { return .passthrough }

        // The caret must be inside the line's leading whitespace. The range is
        // scanned in place on the live source — never materialized as a Swift
        // `String` copy (the line prefix can be the whole document in a
        // pathological single-line file).
        let prefixRange = NSRange(location: start, length: caret - start)
        let isAllWhitespace = text.rangeOfCharacter(
            from: .whitespacesAndNewlines.inverted,
            options: [],
            range: prefixRange
        ).location == NSNotFound
        guard isAllWhitespace else { return .passthrough }

        if character(at: caret - 1, in: text) == 0x09 {
            return .edit(EditingAssistEdit(
                replacementRange: NSRange(location: caret - 1, length: 1),
                replacementString: "",
                resultingSelection: NSRange(location: caret - 1, length: 0),
                undoActionName: "Unindent"
            ))
        }

        let column = caret - start
        let amount = column % width == 0 ? width : column % width
        var trailingSpaces = 0
        var index = caret
        while index > start, character(at: index - 1, in: text) == 0x20 {
            trailingSpaces += 1
            index -= 1
        }
        let remove = min(trailingSpaces, amount)
        guard remove > 0 else { return .passthrough }
        return .edit(EditingAssistEdit(
            replacementRange: NSRange(location: caret - remove, length: remove),
            replacementString: "",
            resultingSelection: NSRange(location: caret - remove, length: 0),
            undoActionName: "Unindent"
        ))
    }

    // MARK: - Selection remap

    /// Maps a selection across a per-line transform using exact UTF-16 deltas.
    static func remappedSelection(
        original: NSRange,
        rangeLocation: Int,
        lineLengths: [Int],
        deltas: [Int],
        newLength: Int
    ) -> NSRange {
        let location = remappedLocation(original.location - rangeLocation, lineLengths: lineLengths, deltas: deltas)
        let end = remappedLocation(
            original.location + original.length - rangeLocation,
            lineLengths: lineLengths,
            deltas: deltas
        )
        let clampedLocation = min(max(0, location), newLength)
        let clampedEnd = min(max(0, end), newLength)
        return NSRange(location: clampedLocation, length: max(0, clampedEnd - clampedLocation))
    }

    /// Maps one UTF-16 position across the per-line deltas: positions inside
    /// a line shift by that line's delta, positions at a line start only by
    /// the deltas of the lines before it.
    static func remappedLocation(_ position: Int, lineLengths: [Int], deltas: [Int]) -> Int {
        var shift = 0
        var lineStart = 0
        for (index, length) in lineLengths.enumerated() {
            let lineEnd = lineStart + length
            if position < lineStart {
                break
            }
            if position == lineStart {
                return position + shift
            }
            if position <= lineEnd {
                return position + shift + deltas[index]
            }
            shift += deltas[index]
            lineStart = lineEnd + 1
        }
        return position + shift
    }

    /// The range covering every line touched by the selection: from the start
    /// of the first line to the content end of the last line, including the
    /// last line's terminating newline when the selection reaches it.
    static func selectedLineRange(text: NSString, selection: NSRange) -> NSRange {
        let start = lineStart(of: selection.location, in: text)
        let lastCharacter = selection.length > 0 ? selection.location + selection.length - 1 : selection.location
        let end = lineContentEnd(of: lastCharacter, in: text)
        var length = end - start
        if end < text.length {
            let separator = character(at: end, in: text)
            let isLF = separator == 0x0A
            let isCRLF = separator == 0x0D && end + 1 < text.length && character(at: end + 1, in: text) == 0x0A
            if isLF || isCRLF, selection.location + selection.length > end {
                length += isLF ? 1 : 2
            }
        }
        return NSRange(location: start, length: length)
    }
}
