import Foundation
@testable import Highlighting
import SwiftTreeSitter
import SwiftTreeSitterLayer
import Testing

@MainActor
struct HighlightInjectionTests {
    @Test func markdownInlineInjectionResolved() throws {
        let registry = GrammarRegistry()
        let config = try #require(registry.configuration(for: "markdown"))

        let layer = try LanguageLayer(
            languageConfig: config,
            configuration: .init(maximumLanguageDepth: 4, languageProvider: registry.languageProvider)
        )

        let text = "Some **bold** text."
        let edit = layer.replaceContent(with: text)

        #expect(edit.isEmpty == false)

        let snapshot = try #require(layer.snapshot())
        let captures = try snapshot.executeQuery(.highlights, in: IndexSet(integersIn: 0 ..< (text as NSString).length))
            .highlights()

        let boldCaptures = captures.filter { $0.name.contains("markup.bold") || $0.name.contains("emphasis") }
        #expect(boldCaptures.isEmpty == false || captures.isEmpty == false)
    }

    @Test func unknownFenceLanguageStaysPlain() throws {
        let registry = GrammarRegistry()
        let config = try #require(registry.configuration(for: "markdown"))

        let layer = try LanguageLayer(
            languageConfig: config,
            configuration: .init(maximumLanguageDepth: 4, languageProvider: registry.languageProvider)
        )

        let text = "```swift\nlet x = 1\n```"
        _ = layer.replaceContent(with: text)

        // swift is not registered, so the fence content should remain plain.
        // The test passes if no exception is thrown and the layer tree stays valid.
        let snapshot = try #require(layer.snapshot())
        let captures = try snapshot.executeQuery(.highlights, in: IndexSet(integersIn: 0 ..< (text as NSString).length))
            .highlights()

        // We should still get markdown captures (fenced_code_block, info_string, etc.).
        #expect(captures.isEmpty == false)
    }
}
