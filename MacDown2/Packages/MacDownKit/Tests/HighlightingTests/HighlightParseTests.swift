import Foundation
@testable import Highlighting
import SwiftTreeSitter
import Testing

@MainActor
struct HighlightParseTests {
    @Test func markdownHeadingsCaptured() throws {
        let captures = try captures(
            languageID: "markdown",
            text: "# Hello\n\n## World\n"
        )
        // The vendored markdown query emits canonical capture names.
        let headings = captures.filter { $0.name == "markup.heading" }
        #expect(headings.count == 2)
    }

    @Test func jsonStringCaptured() throws {
        let captures = try captures(
            languageID: "json",
            text: "{\"key\": \"value\"}"
        )
        let strings = captures.filter { $0.name.hasPrefix("string") }
        #expect(strings.count >= 2)
    }

    @Test func htmlTagCaptured() throws {
        let captures = try captures(
            languageID: "html",
            text: "<div class=\"box\">Hello</div>"
        )
        let tags = captures.filter { $0.name.hasPrefix("tag") }
        #expect(tags.count >= 2)
    }

    @Test func unknownLanguageReturnsNoCaptures() {
        let captures = try? captures(
            languageID: "some-made-up-language",
            text: "anything"
        )
        #expect(captures?.isEmpty != false)
    }

    // MARK: - Helpers

    private func captures(languageID: String, text: String) throws -> [NamedRange] {
        let registry = GrammarRegistry()
        guard let config = registry.configuration(for: languageID) else {
            return []
        }

        let parser = Parser()
        try parser.setLanguage(config.language)

        guard let tree = parser.parse(text),
              let rootNode = tree.rootNode
        else {
            return []
        }

        guard let query = config.queries[.highlights] else {
            return []
        }

        let cursor = query.execute(node: rootNode, in: tree)
        cursor.setRange(NSRange(location: 0, length: (text as NSString).length))

        return cursor.highlights()
    }
}
