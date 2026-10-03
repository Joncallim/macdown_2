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
        #expect(
            PreviewLinkDefinitions.prefixed("[a] and [b]", with: ["[a]: x", "[b]: y"])
                == "[a]: x\n[b]: y\n\n[a] and [b]"
        )
        #expect(PreviewLinkDefinitions.prefixed("body", with: []) == "body")
    }

    @Test func onlyDefinitionsTheBlockReferencesArePrefixed() {
        let definitions = ["[a]: x", "[Big  Label]: y", "[unused]: z"]

        #expect(PreviewLinkDefinitions.prefixed("see [text][a]", with: definitions) == "[a]: x\n\nsee [text][a]")
        #expect(
            PreviewLinkDefinitions.prefixed("see [big label]", with: definitions)
                == "[Big  Label]: y\n\nsee [big label]"
        )
        #expect(PreviewLinkDefinitions.prefixed("no references", with: definitions) == "no references")
    }

    @Test func manyDefinitionsDoNotInflateAnUnrelatedBlock() {
        let definitions = (0 ..< 1500).map { "[label\($0)]: https://example.com/\($0)" }

        #expect(PreviewLinkDefinitions.prefixed("A short paragraph.", with: definitions).utf8.count < 100)
    }

    @Test func labelMatchingFollowsCommonMarkNormalisation() {
        let definitions = ["[foo]: /a", "[Straße]: /b"]

        #expect(PreviewLinkDefinitions.prefixed("see [ foo ]", with: definitions) == "[foo]: /a\n\nsee [ foo ]")
        #expect(PreviewLinkDefinitions.prefixed("see [STRASSE]", with: definitions) == "[Straße]: /b\n\nsee [STRASSE]")
        #expect(PreviewLinkDefinitions.prefixed("see [fo\no]", with: ["[fo o]: /c"]) == "[fo o]: /c\n\nsee [fo\no]")
    }

    @Test func prefixingEveryBlockUsesAPrecomputedIndexAndStaysFast() {
        let definitions = (0 ..< 3000).map { "[label\($0)]: https://example.com/\($0)" }
        let index = PreviewLinkDefinitionIndex(definitions)
        let start = ContinuousClock.now

        for block in 0 ..< 3000 {
            _ = index.prefixed("Paragraph \(block) referencing [label\(block)] only.")
        }

        #expect(ContinuousClock.now - start < .seconds(3))
        #expect(index.prefixed("[label7] and [label9]").hasPrefix("[label7]: https://example.com/7\n[label9]: "))
    }
}
