import Foundation
@testable import MarkdownEngine
import Testing

@MainActor
struct OptionsTests {
    @Test func defaultOptionsEnableBlockDirectives() {
        #expect(MarkdownParseOptions.default.blockDirectives == true)
        #expect(MarkdownParseOptions() == MarkdownParseOptions.default)
    }

    @Test func optionsEquality() {
        #expect(MarkdownParseOptions(blockDirectives: false) != MarkdownParseOptions.default)
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
        let custom = MarkdownParseOptions(blockDirectives: false)

        session.setOptions(custom)
        await Fixtures.wait { await spy.calls.count >= 1 }

        let call = try #require(await spy.calls.first)
        #expect(call.options == custom)
    }
}
