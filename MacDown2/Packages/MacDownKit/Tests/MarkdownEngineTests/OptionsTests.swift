import Foundation
@testable import MarkdownEngine
import Testing

@MainActor
struct OptionsTests {
    @Test func defaultOptionsAreAllEnabled() {
        let options = MarkdownParseOptions.default

        #expect(options.tables == true)
        #expect(options.taskLists == true)
        #expect(options.strikethrough == true)
        #expect(options.autolinks == true)
        #expect(options.footnotes == true)
        #expect(options.blockDirectives == true)
    }

    @Test func optionsEquality() {
        let allOn = MarkdownParseOptions()
        let allOff = MarkdownParseOptions(
            tables: false,
            taskLists: false,
            strikethrough: false,
            autolinks: false,
            footnotes: false
        )

        #expect(allOn == MarkdownParseOptions.default)
        #expect(allOn != allOff)
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
        let custom = MarkdownParseOptions(tables: false)

        session.setOptions(custom)
        await Fixtures.wait { await spy.calls.count >= 1 }

        let call = try #require(await spy.calls.first)
        #expect(call.options == custom)
    }
}
