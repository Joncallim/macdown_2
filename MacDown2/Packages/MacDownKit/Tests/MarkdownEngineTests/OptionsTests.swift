import Foundation
@testable import MarkdownEngine
import Testing

@MainActor
struct OptionsTests {
    @Test func defaultOptionsLeaveBlockDirectivesOff() {
        #expect(MarkdownParseOptions.default.blockDirectives == false)
        #expect(MarkdownParseOptions() == MarkdownParseOptions.default)
    }

    @Test func optionsEquality() {
        #expect(MarkdownParseOptions(blockDirectives: true) != MarkdownParseOptions.default)
    }

    @Test func setOptionsTriggersReparse() async {
        let spy = ParseSpy()
        let session = MarkdownParseSession(engine: spy, debounce: .milliseconds(50))

        session.setOptions(.default)
        await Fixtures.wait { await spy.calls.count >= 1 }

        #expect(await spy.calls.count >= 1)
    }

    @Test func setOptionsPassesNewOptions() async throws {
        let spy = ParseSpy()
        let session = MarkdownParseSession(engine: spy, debounce: .milliseconds(50))
        let custom = MarkdownParseOptions(blockDirectives: true)

        session.setOptions(custom)
        await Fixtures.wait { await spy.calls.count >= 1 }

        let call = try #require(await spy.calls.first)
        #expect(call.options == custom)
    }
}

/// Review pass 1: with block directives on by default, an @-mention line split
/// its paragraph and an unclosed `@Name {` hid the rest of the document.
struct BlockDirectiveDefaultTests {
    @Test func anAtMentionLineDoesNotSplitAParagraphByDefault() async throws {
        let text = "Thanks to the team\n@octocat for the review\nand everyone else.\n"
        let document = try await ParseEngine().parse(text, revision: 1)

        #expect(document.blocks.count == 1)
    }

    @Test func anUnclosedDirectiveOpenerDoesNotHideTheRestOfTheDocument() async throws {
        let text = "Intro paragraph.\n\n@Tom {\n\nNext paragraph\n\n# Heading\n"
        let document = try await ParseEngine().parse(text, revision: 1)

        #expect(document.headings.count == 1)
        #expect(document.blocks.count == 4)
    }

    @Test func directivesStillParseWhenOptedIn() async throws {
        let text = "@Note {\nbody\n}\n"
        let document = try await ParseEngine().parse(
            text,
            options: MarkdownParseOptions(blockDirectives: true),
            revision: 1
        )

        #expect(document.blocks.contains { $0.kind == .custom("BlockDirective") })
    }
}
