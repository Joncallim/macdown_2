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

    /// Regression: Neon's background processor resolves injected languages via
    /// `languageProvider` while the main thread resolves base grammars, so the
    /// shared cache must serialize those concurrent mutations (previously an
    /// unsynchronized `Dictionary` write crashed under `EXC_BREAKPOINT`).
    @Test func configurationIsThreadSafeUnderConcurrentResolution() async {
        let known = ["markdown", "markdown_inline", "json", "html"]
        // Distinct unknown ids force cache growth (misses are cached as nil).
        let unknown = (0 ..< 8).map { "unknown-language-\($0)" }
        let allIDs = known + unknown

        let allCorrect = await withTaskGroup(of: Bool.self) { group in
            for _ in 0 ..< 32 {
                group.addTask {
                    allIDs.allSatisfy { id in
                        (registry.configuration(for: id) != nil) == known.contains(id)
                    }
                }
            }
            var results = [Bool]()
            for await result in group {
                results.append(result)
            }
            return results
        }

        #expect(!allCorrect.contains(false))
        #expect(registry.supportedLanguageIDs.isSuperset(of: known))
    }

    /// Regression: the exact crash path went through `languageProvider`, which
    /// delegates to the same cache as `configuration(for:)`. This test verifies
    /// the closure itself is safe to call concurrently.
    ///
    /// `LanguageProvider` is not declared `@Sendable` by Neon, but the captured
    /// cache is `Sendable` (guarded by `NSLock`), so the closure is safe to
    /// invoke from concurrent tasks. `nonisolated(unsafe)` is used only to
    /// satisfy the test harness; production callers never cross isolation.
    @Test func languageProviderIsThreadSafeUnderConcurrentResolution() async {
        let known = ["markdown", "markdown_inline", "json", "html"]
        let unknown = (0 ..< 8).map { "unknown-language-\($0)" }
        let allIDs = known + unknown

        let provider = registry.languageProvider
        nonisolated(unsafe) let unsafeProvider = provider

        let allCorrect = await withTaskGroup(of: Bool.self) { group in
            for _ in 0 ..< 32 {
                group.addTask {
                    allIDs.allSatisfy { id in
                        (unsafeProvider(id) != nil) == known.contains(id)
                    }
                }
            }
            var results = [Bool]()
            for await result in group {
                results.append(result)
            }
            return results
        }

        #expect(!allCorrect.contains(false))
    }
}
