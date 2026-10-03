import Foundation
import MarkdownEngine
@testable import Preview
import Testing

/// Review pass 1: with any one-line link reference definition in the document, a block
/// that begins `(…)`, `"…"` or `'…'` was swallowed as that definition's title.
struct PreviewLinkDefinitionPrefixTests {
    private let definitions = ["[ref]: https://example.com"]

    @Test(arguments: ["(An aside.)", "\"Quoted whole paragraph.\"", "'Single quoted.'"])
    func aParagraphThatLooksLikeATitleSurvivesTheDefinitionPrefix(paragraph: String) async throws {
        let rendered = PreviewLinkDefinitions.prefixed(paragraph, with: definitions)

        let document = try await ParseEngine().parse(rendered, revision: 1)

        #expect(document.blocks.count == 1)
        #expect(document.blocks.first?.kind == .paragraph)
    }

    @Test func theDefinitionsAreSeparatedByABlankLine() {
        #expect(PreviewLinkDefinitions.prefixed("body", with: ["[a]: x", "[b]: y"]) == "[a]: x\n[b]: y\n\nbody")
        #expect(PreviewLinkDefinitions.prefixed("body", with: []) == "body")
    }
}
