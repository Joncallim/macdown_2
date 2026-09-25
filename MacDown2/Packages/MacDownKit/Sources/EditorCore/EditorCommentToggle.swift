import Foundation

// MARK: - Toggle Comment (EPIC-22 §6.13, Slice 4c-iii)

/// Pure, synchronous logic for Toggle Comment — the last of Slice 4c's ten
/// built-in transforms. Reuses `EditorLineTransforms`' own line-block
/// merging (the same "two carets on the same/adjacent lines must not
/// produce overlapping replacements" concern every other multi-line
/// transform in this epic already solved) and `EditorLineTransforms.makeTransaction`.
///
/// "Smart toggle" semantics (VSCode/Sublime/Xcode's shared convention): if
/// every touched line already starts (after its own leading whitespace)
/// with the effective profile's `lineComment` prefix, remove it from every
/// line that has it; otherwise add it to every line that doesn't. A profile
/// with no `lineComment` (Markdown, HTML, XML, CSS in this codebase's own
/// registry — a REAL, common case, not a rare edge case) falls back to
/// wrapping the whole block once with `blockComment`'s `open`/`close`
/// instead. A profile with neither declines the WHOLE command (matching
/// this epic's established "the whole command disables rather than
/// silently half-applying" precedent for Sort/Dedupe/Indent) — a MIXED
/// selection where one merged group's own effective profile has comment
/// syntax and another's doesn't is treated the same way, not partially
/// applied.
enum EditorCommentToggle {
    static func toggleCommentTransaction(
        text: NSString,
        lineIndex: EditorLineIndex,
        selection: EditorSelectionSet,
        isMarkdownFormat: Bool,
        profile: LanguageEditingProfile
    ) -> EditorEditTransaction? {
        let groups = EditorLineTransforms.mergedLineBlockGroups(for: selection, lineIndex: lineIndex)
        guard !groups.isEmpty else { return nil }

        var replacements: [TextReplacement] = []
        var resultsByOriginalIndex: [Int: NSRange] = [:]
        var delta = 0

        for group in groups {
            let effectiveProfile = isMarkdownFormat
                ? fenceAwareProfile(forAnchorLine: group.startLine, text: text, lineIndex: lineIndex, fallback: profile)
                : profile
            guard let outcome = toggleOutcome(for: group, text: text, lineIndex: lineIndex, profile: effectiveProfile)
            else {
                return nil
            }

            replacements.append(TextReplacement(range: outcome.range, replacementText: outcome.newContent))
            for index in group.memberIndices {
                let original = selection.ranges[index]
                let shifted = outcome.remap(original)
                resultsByOriginalIndex[index] = NSRange(location: shifted.location + delta, length: shifted.length)
            }
            delta += (outcome.newContent as NSString).length - outcome.range.length
        }

        return EditorLineTransforms.makeTransaction(
            replacements: replacements,
            resultsByOriginalIndex: resultsByOriginalIndex,
            selection: selection,
            undoActionName: "Toggle Comment"
        )
    }

    /// Resolves the profile Markdown's own comment-toggle should actually
    /// use at `anchorLine` — exactly the way `MarkdownEditingAssistEngine`'s
    /// `effectiveConfigurationAndProfile` already resolves it for ambient
    /// typing assists (§6.12): the fenced language's own profile when
    /// `anchorLine` is inside a fence (Markdown has no line-comment syntax
    /// of its own to toggle there), `.plainText` inside front matter,
    /// `fallback` (the document's own Markdown profile) in ordinary prose.
    /// A selection spanning both a fence and surrounding prose is scoped
    /// entirely to whichever profile ITS OWN anchor line resolves to — a
    /// mixed per-line profile within one selection would make the smart-
    /// toggle "already commented?" check itself ambiguous.
    private static func fenceAwareProfile(
        forAnchorLine anchorLine: Int,
        text: NSString,
        lineIndex: EditorLineIndex,
        fallback: LanguageEditingProfile
    ) -> LanguageEditingProfile {
        let anchorOffset = lineIndex.lineStartOffsets[anchorLine - 1]
        switch FencedRegionClassifier.classify(text: text, atUTF16Offset: anchorOffset) {
        case .prose:
            return fallback
        case .frontMatter:
            return .plainText
        case let .fencedCode(languageID):
            return languageID.map { LanguageEditingProfileRegistry.profile(for: $0) } ?? .plainText
        }
    }

    /// One group's own toggle result: the replacement itself, plus a
    /// closure remapping any ORIGINAL absolute position within the group to
    /// its own final absolute position (before this group's own contribution
    /// to the cross-group cumulative `delta` other groups also need).
    private struct ToggleOutcome {
        let range: NSRange
        let newContent: String
        let remap: (NSRange) -> NSRange
    }

    private static func toggleOutcome(
        for group: EditorLineTransforms.LineBlockGroup,
        text: NSString,
        lineIndex: EditorLineIndex,
        profile: LanguageEditingProfile
    ) -> ToggleOutcome? {
        let groupStart = lineIndex.lineStartOffsets[group.startLine - 1]
        let endContentRange = lineIndex.utf16Range(ofLine: group.endLine, in: text)
        let groupRange = NSRange(
            location: groupStart,
            length: endContentRange.location + endContentRange.length - groupStart
        )
        let groupContent = text.substring(with: groupRange)

        if let lineComment = profile.lineComment {
            let lines = groupContent.components(separatedBy: "\n")
            let (newLines, lineDeltas) = lineCommentToggle(lines: lines, prefix: lineComment)
            let newContent = newLines.joined(separator: "\n")
            let lineLengths = lines.map { ($0 as NSString).length }
            let newLength = (newContent as NSString).length
            return ToggleOutcome(range: groupRange, newContent: newContent) { original in
                let remapped = MarkdownEditingAssistEngine.remappedSelection(
                    original: original,
                    rangeLocation: groupRange.location,
                    lineLengths: lineLengths,
                    deltas: lineDeltas,
                    newLength: newLength
                )
                return NSRange(location: groupRange.location + remapped.location, length: remapped.length)
            }
        }

        if let blockComment = profile.blockComment {
            let (newContent, shift) = blockCommentToggle(
                groupContent,
                open: blockComment.open,
                close: blockComment.close
            )
            return ToggleOutcome(range: groupRange, newContent: newContent) { original in
                NSRange(location: original.location + shift, length: original.length)
            }
        }

        return nil
    }

    /// Per-line smart toggle: if EVERY line (after its own leading
    /// whitespace) already starts with `prefix`, strip it (plus one
    /// following space, if present) from each; otherwise add `prefix + " "`
    /// to every line that doesn't already have it. Blank lines are not
    /// special-cased — an all-blank block being "commented" gets the
    /// prefix inserted into its own blank lines too, matching this being a
    /// simple, disclosed v1 rather than every editor's own fancier
    /// blank-line handling.
    private static func lineCommentToggle(lines: [String], prefix: String) -> (lines: [String], deltas: [Int]) {
        let allCommented = lines.allSatisfy { line in
            let leadingWhitespace = line.prefix { $0 == " " || $0 == "\t" }
            return line.dropFirst(leadingWhitespace.count).hasPrefix(prefix)
        }
        var deltas: [Int] = []
        let processed = lines.map { line -> String in
            let leadingWhitespace = line.prefix { $0 == " " || $0 == "\t" }
            let rest = line.dropFirst(leadingWhitespace.count)
            if allCommented {
                var afterPrefix = rest.dropFirst(prefix.count)
                var removedLength = (prefix as NSString).length
                if afterPrefix.first == " " {
                    afterPrefix = afterPrefix.dropFirst()
                    removedLength += 1
                }
                deltas.append(-removedLength)
                return String(leadingWhitespace) + afterPrefix
            }
            guard !rest.hasPrefix(prefix) else {
                deltas.append(0)
                return line
            }
            let inserted = prefix + " "
            deltas.append((inserted as NSString).length)
            return String(leadingWhitespace) + inserted + rest
        }
        return (processed, deltas)
    }

    /// Whole-block toggle for a `lineComment`-less profile: if `content`
    /// already starts with `open` and ends with `close`, strip them;
    /// otherwise wrap. `shift` is how much every position AT OR AFTER the
    /// block's own start moves by (positive when wrapping, negative when
    /// stripping) — a fixed amount, since this is a single insertion/
    /// deletion at the block's own start, unlike the per-line case.
    private static func blockCommentToggle(_ content: String, open: String,
                                           close: String) -> (content: String, shift: Int) {
        let openLength = (open as NSString).length
        let closeLength = (close as NSString).length
        if content.hasPrefix(open), content.hasSuffix(close),
           (content as NSString).length >= openLength + closeLength {
            let contentNSString = content as NSString
            let inner = contentNSString.substring(
                with: NSRange(location: openLength, length: contentNSString.length - openLength - closeLength)
            )
            return (inner, -openLength)
        }
        return (open + content + close, openLength)
    }
}
