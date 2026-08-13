import Foundation

// MARK: - Internal action

/// The normalized input the adapter feeds into the pure engine.
enum EditingAssistAction: Equatable {
    /// A typed replacement (character or paste) at `range`.
    case replacement(range: NSRange, string: String)
    /// The Return key (`insertNewline:`).
    case insertNewline
    /// The Tab key (`insertTab:`).
    case insertTab
    /// Shift-Tab (`insertBacktab:`).
    case insertBacktab
    /// Backspace (`deleteBackward:`).
    case deleteBackward
    /// Smart Home (`moveToLeftEndOfLine:`).
    case smartHome
    /// A Markdown formatting menu command.
    case markdownCommand(MarkdownEditingCommand)
}

// MARK: - Line prefix model

/// A `[ ]` / `[x]` / `[X]` task marker. Continuation always emits `[ ]`.
enum TaskMarker: Equatable {
    case unchecked
    case checked
}

enum ListMarker: Equatable {
    case unordered(Character)
    case ordered(rawDigits: String)
}

/// The recognized Markdown line prefix before the caret:
/// `[indentation][zero or more > markers][list marker][task marker]`.
struct MarkdownLinePrefix: Equatable {
    let indentation: String
    let blockquotePrefix: String
    let listMarker: ListMarker?
    let taskMarker: TaskMarker?
    /// Range of the content between the recognized construct and the caret.
    let contentRangeInLine: NSRange
}

// MARK: - Engine

/// Pure, synchronous, UTF-16-local decision layer for E10 editing assists.
///
/// The engine never mutates `text`, never materializes a whole-document Swift
/// `String`, never runs Markdown parsing, and never allocates async work. All
/// offsets are UTF-16 (`NSRange`, `NSString.length`).
enum MarkdownEditingAssistEngine {
    /// The single entry point: decides the outcome for one input action.
    static func outcome(
        for action: EditingAssistAction,
        text: NSString,
        selection: NSRange,
        configuration: EditingAssistConfiguration
    ) -> EditingAssistOutcome {
        guard configuration.isEnabled else { return .passthrough }

        let clampedSelection = clampedRange(selection, length: text.length)
        switch action {
        case let .replacement(range, string):
            return replacementOutcome(
                range: clampedRange(range, length: text.length),
                string: string,
                text: text,
                selection: clampedSelection,
                configuration: configuration
            )
        case .insertNewline:
            return newlineOutcome(text: text, selection: clampedSelection, configuration: configuration)
        case .insertTab:
            return tabOutcome(text: text, selection: clampedSelection, configuration: configuration, shift: false)
        case .insertBacktab:
            return tabOutcome(text: text, selection: clampedSelection, configuration: configuration, shift: true)
        case .deleteBackward:
            return backspaceOutcome(text: text, selection: clampedSelection, configuration: configuration)
        case .smartHome:
            return smartHomeOutcome(text: text, selection: clampedSelection, configuration: configuration)
        case let .markdownCommand(command):
            return commandOutcome(command: command, text: text, selection: clampedSelection)
        }
    }

    // MARK: - Typed replacement

    private static func replacementOutcome(
        range: NSRange,
        string: String,
        text: NSString,
        selection _: NSRange,
        configuration: EditingAssistConfiguration
    ) -> EditingAssistOutcome {
        guard configuration.completesMatchingCharacters else { return .passthrough }
        guard string.utf16.count == 1 else { return .passthrough }
        guard let unit = string.utf16.first, let scalar = UnicodeScalar(unit) else {
            return .passthrough
        }
        let character = Character(scalar)

        if range.length > 0 {
            return wrapOutcome(character: character, selection: range, text: text)
        }
        return collapsedTypingOutcome(character: character, caret: range.location, text: text)
    }

    /// Wrapping a non-empty selection with a structural opener or a symmetric
    /// Markdown delimiter. The logical content stays selected so a second
    /// same-delimiter wrap produces strong emphasis naturally.
    private static func wrapOutcome(character: Character, selection: NSRange, text: NSString) -> EditingAssistOutcome {
        let content = text.substring(with: selection)
        let prefix: String
        let suffix: String
        if let closer = structuralCloser(for: character) {
            prefix = String(character)
            suffix = String(closer)
        } else if character == "*" || character == "_" || character == "`" {
            prefix = String(character)
            suffix = String(character)
        } else {
            return .passthrough
        }
        return .edit(EditingAssistEdit(
            replacementRange: selection,
            replacementString: prefix + content + suffix,
            resultingSelection: NSRange(location: selection.location + prefix.utf16.count, length: selection.length),
            undoActionName: "Insert"
        ))
    }

    private static func collapsedTypingOutcome(character: Character, caret: Int,
                                               text: NSString) -> EditingAssistOutcome
    // swiftlint:disable:next opening_brace
    {
        let next = scalar(at: caret, in: text)
        let previous = scalar(before: caret, in: text)

        // Type-over: the typed character is already the immediate next
        // delimiter character (structural closer or symmetric delimiter).
        // This also covers the `*|*` shape: replacing the two stars with the
        // same pair and moving the caret one unit right is an identity edit,
        // which is what lets strong emphasis be typed naturally and lets the
        // closing pair of `**…**` be typed with one keystroke per star.
        if let next, Character(next) == character, isTypeOverTarget(character) {
            return .selection(NSRange(location: caret + utf16Length(of: next), length: 0))
        }

        if let closer = structuralCloser(for: character) {
            return structuralPairOutcome(
                character: character,
                closer: closer,
                caret: caret,
                previous: previous,
                next: next
            )
        }
        return symmetricDelimiterOutcome(character: character, caret: caret, previous: previous, next: next, text: text)
    }

    private static func isTypeOverTarget(_ character: Character) -> Bool {
        if structuralPairs.contains(where: { $0.closer == character }) {
            return true
        }
        return character == "*" || character == "_" || character == "`"
    }

    /// Structural pair completion (with the permissive legacy previous-
    /// character behavior), plus the symmetric-quote previous-boundary rule.
    private static func structuralPairOutcome(
        character: Character,
        closer: Character,
        caret: Int,
        previous: Unicode.Scalar?,
        next: Unicode.Scalar?
    ) -> EditingAssistOutcome {
        let nextIsBoundary = next.map(isBoundary) ?? true
        guard nextIsBoundary else { return .passthrough }
        if character == closer {
            // Symmetric quote: also require a previous boundary/end.
            let previousIsBoundary = previous.map(isBoundary) ?? true
            guard previousIsBoundary else { return .passthrough }
        }
        return pairInsertion(character: character, closer: closer, caret: caret)
    }

    /// Symmetric Markdown delimiter pairing (`*`, `_`, backtick).
    private static func symmetricDelimiterOutcome(
        character: Character,
        caret: Int,
        previous: Unicode.Scalar?,
        next: Unicode.Scalar?,
        text: NSString
    ) -> EditingAssistOutcome {
        let nextIsBoundary = next.map(isBoundary) ?? true
        switch character {
        case "*":
            // At the first non-whitespace position of a line, do not auto-pair
            // a single `*`, so `* ` unordered-list typing stays natural.
            // Likewise never pair after an existing `*`: the second star of a
            // line-start `**`/`***` opener must insert natively.
            guard !isAtFirstNonWhitespace(caret, in: text) else { return .passthrough }
            if previous.map({ Character($0) == "*" }) == true {
                return .passthrough
            }
            guard nextIsBoundary else { return .passthrough }
            return pairInsertion(character: "*", closer: "*", caret: caret)
        case "_":
            // Pair only at a boundary; never auto-pair intra-word underscore.
            let previousBoundary = previous.map(isBoundary) ?? true
            guard previousBoundary || nextIsBoundary else { return .passthrough }
            return pairInsertion(character: "_", closer: "_", caret: caret)
        case "`":
            guard nextIsBoundary else { return .passthrough }
            return pairInsertion(character: "`", closer: "`", caret: caret)
        default:
            return .passthrough
        }
    }

    private static func pairInsertion(character: Character, closer: Character, caret: Int) -> EditingAssistOutcome {
        let pair = String(character) + String(closer)
        return .edit(EditingAssistEdit(
            replacementRange: NSRange(location: caret, length: 0),
            replacementString: pair,
            resultingSelection: NSRange(location: caret + 1, length: 0),
            undoActionName: "Insert"
        ))
    }

    /// True when the caret is at the first non-whitespace position of its line.
    ///
    /// Scans backward from the caret so the common case (content immediately
    /// before the caret) exits after one unit instead of walking the whole
    /// line prefix, keeping the `*`-keypress decision local even at the end
    /// of a very long line.
    private static func isAtFirstNonWhitespace(_ caret: Int, in text: NSString) -> Bool {
        let start = lineStart(of: caret, in: text)
        var prefixEnd = start
        while prefixEnd < caret, isHorizontalWhitespace(character(at: prefixEnd, in: text)) {
            prefixEnd += 1
        }
        while prefixEnd < caret, character(at: prefixEnd, in: text) == 0x3E {
            prefixEnd += 1
            if prefixEnd < caret, character(at: prefixEnd, in: text) == 0x20 {
                prefixEnd += 1
            }
            while prefixEnd < caret, isHorizontalWhitespace(character(at: prefixEnd, in: text)) {
                prefixEnd += 1
            }
        }
        var index = caret
        while index > prefixEnd {
            let unit = character(at: index - 1, in: text)
            if unit != 0x20, unit != 0x09 {
                return false
            }
            index -= 1
        }
        return true
    }

    // MARK: - Paired Backspace

    private static func backspaceOutcome(
        text: NSString,
        selection: NSRange,
        configuration: EditingAssistConfiguration
    ) -> EditingAssistOutcome {
        guard configuration.completesMatchingCharacters else { return .passthrough }
        guard selection.length == 0 else { return .passthrough }
        let caret = selection.location
        guard caret > 0, caret < text.length else { return .passthrough }

        let previous = scalar(before: caret, in: text)
        let next = scalar(at: caret, in: text)
        guard let previous, let next else { return .passthrough }

        // Structural pair.
        if let opener = structuralOpener(for: Character(next)), Character(previous) == opener {
            let range = NSRange(
                location: caret - utf16Length(of: previous),
                length: utf16Length(of: previous) + utf16Length(of: next)
            )
            return deletePair(range: range)
        }

        // Symmetric Markdown pair (`*|*`, `_|_`, `` `|` ``).
        let previousCharacter = Character(previous)
        if previous == next, previousCharacter == "*" || previousCharacter == "_" || previousCharacter == "`" {
            return deletePair(range: NSRange(location: caret - 1, length: 2))
        }

        return .passthrough
    }

    private static func deletePair(range: NSRange) -> EditingAssistOutcome {
        .edit(EditingAssistEdit(
            replacementRange: range,
            replacementString: "",
            resultingSelection: NSRange(location: range.location, length: 0),
            undoActionName: "Delete"
        ))
    }

    // MARK: - Smart Home

    private static func smartHomeOutcome(
        text: NSString,
        selection: NSRange,
        configuration: EditingAssistConfiguration
    ) -> EditingAssistOutcome {
        guard configuration.smartHome else { return .passthrough }
        let caret = selection.location
        let start = lineStart(of: caret, in: text)
        let contentEnd = lineContentEnd(of: caret, in: text)

        let nonWhitespace = firstNonWhitespace(in: text, from: start, to: contentEnd)
        let target: Int = if let nonWhitespace, caret != nonWhitespace {
            nonWhitespace
        } else {
            start
        }
        return .selection(NSRange(location: target, length: 0))
    }
}
