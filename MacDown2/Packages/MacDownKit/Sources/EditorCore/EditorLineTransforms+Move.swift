import Foundation

// MARK: - Move Line Up / Down (EPIC-22 §6.13, Slice 4c-i)

/// Extracted from `EditorLineTransforms.swift` to stay under swiftlint's
/// type-body-length limit once Duplicate/Delete/Join were also added there.
extension EditorLineTransforms {
    static func moveLinesUpTransaction(
        text: NSString,
        lineIndex: EditorLineIndex,
        selection: EditorSelectionSet
    ) -> EditorEditTransaction? {
        moveLinesTransaction(text: text, lineIndex: lineIndex, selection: selection, moveUp: true)
    }

    static func moveLinesDownTransaction(
        text: NSString,
        lineIndex: EditorLineIndex,
        selection: EditorSelectionSet
    ) -> EditorEditTransaction? {
        moveLinesTransaction(text: text, lineIndex: lineIndex, selection: selection, moveUp: false)
    }

    /// Every active group must have room to move in the requested direction
    /// (all-or-nothing, matching this codebase's established "the whole
    /// command disables/no-ops rather than silently half-applying" — §6.13
    /// — precedent for Sort/Dedupe/case conversion).
    private static func moveLinesTransaction(
        text: NSString,
        lineIndex: EditorLineIndex,
        selection: EditorSelectionSet,
        moveUp: Bool
    ) -> EditorEditTransaction? {
        let groups = mergedLineBlockGroups(for: selection, lineIndex: lineIndex)
        guard !groups.isEmpty else { return nil }
        guard moveUp
            ? groups.allSatisfy({ $0.startLine > 1 })
            : groups.allSatisfy({ $0.endLine < lineIndex.lineCount })
        else { return nil }

        var replacements: [TextReplacement] = []
        var resultsByOriginalIndex: [Int: NSRange] = [:]
        var delta = 0

        for group in groups {
            let blockStart = lineIndex.lineStartOffsets[group.startLine - 1]
            let (replacement, blockOffsetInNewContent) = swapReplacement(
                startLine: group.startLine,
                endLine: group.endLine,
                moveUp: moveUp,
                lineIndex: lineIndex,
                text: text
            )
            replacements.append(replacement)

            let newBlockStart = replacement.range.location + blockOffsetInNewContent
            for index in group.memberIndices {
                let original = selection.ranges[index]
                let offset = original.location - blockStart
                resultsByOriginalIndex[index] = NSRange(
                    location: newBlockStart + offset + delta,
                    length: original.length
                )
            }

            delta += (replacement.replacementText as NSString).length - replacement.range.length
        }

        return makeTransaction(
            replacements: replacements,
            resultsByOriginalIndex: resultsByOriginalIndex,
            selection: selection,
            undoActionName: moveUp ? "Move Line Up" : "Move Line Down"
        )
    }

    /// Rearranges the block `[startLine...endLine]` and the single adjacent
    /// line (above for `moveUp`, below otherwise) via one pure content
    /// swap over their exact combined span — the same set of lines, in a
    /// new order, joined by the same `"\n"` separators, replacing the
    /// identical span they already occupied. No terminator bookkeeping is
    /// needed beyond this: whatever precedes/follows the combined span
    /// (including "nothing, this is the document's last line") is
    /// completely untouched.
    private static func swapReplacement(
        startLine: Int,
        endLine: Int,
        moveUp: Bool,
        lineIndex: EditorLineIndex,
        text: NSString
    ) -> (replacement: TextReplacement, blockOffsetInNewContent: Int) {
        let adjacentLine = moveUp ? startLine - 1 : endLine + 1
        let spanStartLine = moveUp ? adjacentLine : startLine
        let spanEndLine = moveUp ? endLine : adjacentLine

        let spanStart = lineIndex.utf16Range(ofLine: spanStartLine, in: text).location
        let spanEndLineRange = lineIndex.utf16Range(ofLine: spanEndLine, in: text)
        let spanEnd = spanEndLineRange.location + spanEndLineRange.length
        let combinedRange = NSRange(location: spanStart, length: spanEnd - spanStart)

        let blockLines = (startLine ... endLine)
            .map { text.substring(with: lineIndex.utf16Range(ofLine: $0, in: text)) }
        let adjacentContent = text.substring(with: lineIndex.utf16Range(ofLine: adjacentLine, in: text))

        let orderedLines = moveUp ? blockLines + [adjacentContent] : [adjacentContent] + blockLines
        let newContent = orderedLines.joined(separator: "\n")
        let replacement = TextReplacement(range: combinedRange, replacementText: newContent)

        let blockOffsetInNewContent = moveUp ? 0 : (adjacentContent as NSString).length + 1
        return (replacement, blockOffsetInNewContent)
    }
}
