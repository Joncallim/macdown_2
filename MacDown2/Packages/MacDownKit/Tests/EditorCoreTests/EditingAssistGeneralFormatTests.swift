@testable import EditorCore
import Foundation
import Testing

/// EPIC-22 §6.11, Slice 4a — generalizing the pairing/indent engine to every
/// format via `LanguageEditingProfile`, and `LanguageEditingProfileRegistry`
/// itself.
@Suite("Editing assists — general (non-Markdown) format support")
struct EditingAssistGeneralFormatTests {
    private let support = EditingAssistTestSupport.self

    private static let swiftProfile = LanguageEditingProfileRegistry.profile(for: "swift")

    // MARK: - Structural pairing, every format

    @Test("structural pairing fires under .general configuration")
    func structuralPairingFiresUnderGeneralConfiguration() {
        let outcome = support.type("(", in: "foo", at: 3, configuration: .general, profile: Self.swiftProfile)

        #expect(support.applied(outcome, to: "foo")?.text == "foo()")
    }

    @Test("Markdown symmetric delimiters do NOT fire under .general configuration")
    func markdownDelimitersDoNotFireUnderGeneralConfiguration() {
        let outcome = support.type("*", in: "foo", at: 3, configuration: .general, profile: Self.swiftProfile)

        #expect(outcome == .passthrough)
    }

    @Test("structural backspace fires under .general configuration")
    func structuralBackspaceFiresUnderGeneralConfiguration() {
        let outcome = support.outcome(
            for: .deleteBackward,
            in: "foo()",
            selection: NSRange(location: 4, length: 0),
            configuration: .general,
            profile: Self.swiftProfile
        )

        #expect(support.applied(outcome, to: "foo()")?.text == "foo")
    }

    @Test("Markdown symmetric backspace does NOT fire under .general configuration")
    func markdownSymmetricBackspaceDoesNotFireUnderGeneralConfiguration() {
        let outcome = support.outcome(
            for: .deleteBackward,
            in: "foo**bar",
            selection: NSRange(location: 4, length: 0),
            configuration: .general,
            profile: Self.swiftProfile
        )

        #expect(outcome == .passthrough)
    }

    // MARK: - Profile-driven indent width (Tab/Shift-Tab)

    @Test("a profile's defaultIndentWidth overrides the global indentationWidth for Tab")
    func profileIndentWidthOverridesTabWidth() {
        var configuration = EditingAssistConfiguration.general
        configuration.indentationWidth = 4
        let profile = LanguageEditingProfile(defaultIndentWidth: 2)

        // Caret at column 0 (start of line): "spaces to the next indentation
        // stop" is then unambiguously the full width itself, not a partial
        // remainder -- isolating exactly what this test means to check.
        let outcome = support.outcome(
            for: .insertTab,
            in: "x",
            selection: NSRange(location: 0, length: 0),
            configuration: configuration,
            profile: profile
        )

        #expect(support.applied(outcome, to: "x")?.text == "  x") // 2 spaces, not the global 4
    }

    @Test("Tab falls back to the global indentationWidth when the profile has none")
    func tabFallsBackToGlobalWidthWithoutAProfileOverride() {
        var configuration = EditingAssistConfiguration.general
        configuration.indentationWidth = 3

        let outcome = support.outcome(
            for: .insertTab,
            in: "x",
            selection: NSRange(location: 0, length: 0),
            configuration: configuration,
            profile: .plainText
        )

        #expect(support.applied(outcome, to: "x")?.text == "   x") // 3 spaces
    }

    // MARK: - General Return-key indentation

    @Test("Return maintains the previous line's indentation under .general configuration")
    func returnMaintainsIndentationUnderGeneralConfiguration() {
        let text = "    let x = 1"
        let outcome = support.outcome(
            for: .insertNewline,
            in: text,
            selection: NSRange(location: text.utf16.count, length: 0),
            configuration: .general,
            profile: Self.swiftProfile
        )

        let result = support.applied(outcome, to: text)
        #expect(result?.text == "    let x = 1\n    ")
    }

    @Test("Return with no leading indentation and no trigger character is a no-op")
    func returnIsANoOpWithNoIndentationOrTrigger() {
        let text = "let x = 1"
        let outcome = support.outcome(
            for: .insertNewline,
            in: text,
            selection: NSRange(location: text.utf16.count, length: 0),
            configuration: .general,
            profile: Self.swiftProfile
        )

        #expect(outcome == .passthrough)
    }

    @Test("Return adds one further indent level after a profile's indentAfterTrailing character")
    func returnAddsOneMoreLevelAfterATrailingTriggerCharacter() {
        var configuration = EditingAssistConfiguration.general
        configuration.indentationWidth = 4
        let profile = LanguageEditingProfile(indentAfterTrailing: ["{"])
        let text = "func f() {"

        let outcome = support.outcome(
            for: .insertNewline,
            in: text,
            selection: NSRange(location: text.utf16.count, length: 0),
            configuration: configuration,
            profile: profile
        )

        let result = support.applied(outcome, to: text)
        #expect(result?.text == "func f() {\n    ") // no prior indentation + 4 new spaces
    }

    @Test("Return combines existing indentation with the extra trailing-trigger level")
    func returnCombinesExistingIndentationWithTheExtraLevel() {
        var configuration = EditingAssistConfiguration.general
        configuration.indentationWidth = 2
        let profile = LanguageEditingProfile(indentAfterTrailing: ["{"])
        let text = "  func f() {"

        let outcome = support.outcome(
            for: .insertNewline,
            in: text,
            selection: NSRange(location: text.utf16.count, length: 0),
            configuration: configuration,
            profile: profile
        )

        let result = support.applied(outcome, to: text)
        #expect(result?.text == "  func f() {\n    ") // 2 existing + 2 new
    }

    @Test("Return does not run Markdown list/blockquote continuation under .general configuration")
    func returnDoesNotContinueMarkdownConstructsUnderGeneralConfiguration() {
        let text = "- item one"
        let outcome = support.outcome(
            for: .insertNewline,
            in: text,
            selection: NSRange(location: text.utf16.count, length: 0),
            configuration: .general,
            profile: Self.swiftProfile
        )

        // No list-marker continuation -- just the (empty) leading indentation
        // maintained, which here is empty, so this is a no-op/passthrough.
        #expect(outcome == .passthrough)
    }

    // MARK: - `LanguageEditingProfileRegistry`

    @Test("registry returns a comment-aware profile for a known format")
    func registryReturnsAKnownProfile() {
        let profile = LanguageEditingProfileRegistry.profile(for: "swift")

        #expect(profile.lineComment == "//")
        #expect(profile.blockComment == BlockCommentDelimiters(open: "/*", close: "*/"))
        #expect(profile.indentAfterTrailing.contains("{"))
    }

    @Test("registry falls back to .plainText for an unregistered format id")
    func registryFallsBackToPlainTextForUnknownFormats() {
        let profile = LanguageEditingProfileRegistry.profile(for: "some-future-format")

        #expect(profile == .plainText)
    }

    @Test("registry's markdown entry has no line comment but a block comment for prose comment-toggle")
    func registryMarkdownEntryHasNoLineCommentButABlockComment() {
        let profile = LanguageEditingProfileRegistry.profile(for: "markdown")

        #expect(profile.lineComment == nil)
        #expect(profile.blockComment == BlockCommentDelimiters(open: "<!--", close: "-->"))
    }
}
