@testable import Highlighting
import Testing

@MainActor
struct GrammarRegistryTests {
    private let registry = GrammarRegistry()

    @Test func markdownConfigExists() {
        #expect(registry.configuration(for: "markdown") != nil)
    }

    @Test func jsonConfigExists() {
        #expect(registry.configuration(for: "json") != nil)
    }

    @Test func htmlConfigExists() {
        #expect(registry.configuration(for: "html") != nil)
    }

    @Test func unknownIDReturnsNil() {
        #expect(registry.configuration(for: "some-made-up-language") == nil)
    }

    @Test func nilIDReturnsNil() {
        #expect(registry.configuration(for: nil) == nil)
    }

    @Test func languageProviderResolvesMarkdownInline() {
        let provider = registry.languageProvider
        #expect(provider("markdown_inline") != nil)
    }

    @Test func languageProviderReturnsNilForUnknown() {
        let provider = registry.languageProvider
        #expect(provider("swift") == nil)
    }

    @Test func supportedLanguageIDsAreTracked() {
        _ = registry.configuration(for: "markdown")
        _ = registry.configuration(for: "json")
        _ = registry.configuration(for: "html")
        #expect(registry.supportedLanguageIDs.contains("markdown"))
        #expect(registry.supportedLanguageIDs.contains("json"))
        #expect(registry.supportedLanguageIDs.contains("html"))
    }
}
