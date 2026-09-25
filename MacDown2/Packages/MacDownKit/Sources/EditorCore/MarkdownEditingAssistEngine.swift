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
    ///
    /// `profile` is the active document format's `LanguageEditingProfile`
    /// (EPIC-22 §6.11, Slice 4a) — required, not defaulted, so every call
    /// site states explicitly which profile is in effect rather than
    /// silently falling back to `.plainText`. It drives general, per-format
    /// mechanics (structural pairing, indent width, indent-after-trailing);
    /// Markdown's own symmetric-delimiter/list/heading behavior is
    /// unaffected by it and continues to key off `configuration`'s
    /// Markdown-specific flags alone.
    static func outcome(
        for action: EditingAssistAction,
        text: NSString,
        selection: NSRange,
        configuration: EditingAssistConfiguration,
        profile: LanguageEditingProfile
    ) -> EditingAssistOutcome {
        guard configuration.isEnabled else { return .passthrough }

        let clampedSelection = clampedRange(selection, length: text.length)
        switch action {
        case let .replacement(range, string):
            return replacementOutcome(
                range: clampedRange(range, length: text.length),
                string: string,
                text: text,
                configuration: configuration,
                profile: profile
            )
        case .insertNewline:
            return newlineOutcome(
                text: text,
                selection: clampedSelection,
                configuration: configuration,
                profile: profile
            )
        case .insertTab:
            return tabOutcome(
                text: text,
                selection: clampedSelection,
                configuration: configuration,
                profile: profile,
                shift: false
            )
        case .insertBacktab:
            return tabOutcome(
                text: text,
                selection: clampedSelection,
                configuration: configuration,
                profile: profile,
                shift: true
            )
        case .deleteBackward:
            return backspaceOutcome(
                text: text,
                selection: clampedSelection,
                configuration: configuration,
                profile: profile
            )
        case .smartHome:
            return smartHomeOutcome(text: text, selection: clampedSelection, configuration: configuration)
        case let .markdownCommand(command):
            return commandOutcome(command: command, text: text, selection: clampedSelection)
        }
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
