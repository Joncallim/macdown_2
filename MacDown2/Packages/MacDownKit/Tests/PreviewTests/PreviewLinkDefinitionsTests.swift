@testable import Preview
import Testing

@Suite("PreviewBlock oversize guard")
struct PreviewBlockOversizeTests {
    @Test func typicalBlockIsNotOversize() {
        let block = PreviewBlock(kind: .paragraph, source: "Just a normal paragraph.", lineRange: 1 ... 1)
        #expect(block.isOversize == false)
    }

    @Test func blockAtExactlyTheThresholdIsNotOversize() {
        let source = String(repeating: "a", count: PreviewBlock.oversizeByteThreshold)
        let block = PreviewBlock(kind: .codeBlock(language: nil), source: source, lineRange: 1 ... 1)
        #expect(source.utf8.count == PreviewBlock.oversizeByteThreshold)
        #expect(block.isOversize == false)
    }

    @Test func blockOneByteOverTheThresholdIsOversize() {
        let source = String(repeating: "a", count: PreviewBlock.oversizeByteThreshold + 1)
        let block = PreviewBlock(kind: .codeBlock(language: nil), source: source, lineRange: 1 ... 1)
        #expect(block.isOversize == true)
    }

    // Regression: a single oversize code fence should degrade on its own,
    // without any other block in the document being affected — this is the
    // scenario a large pasted log or minified bundle produces.
    @Test func oversizeGuardIsPerBlockNotPerDocument() {
        let normal = PreviewBlock(kind: .paragraph, source: "short", lineRange: 1 ... 1)
        let big = PreviewBlock(
            kind: .codeBlock(language: "text"),
            source: String(repeating: "x", count: PreviewBlock.oversizeByteThreshold * 2),
            lineRange: 3 ... 3
        )
        #expect(normal.isOversize == false)
        #expect(big.isOversize == true)
    }
}

@Suite("PreviewLinkDefinitions")
struct PreviewLinkDefinitionsTests {
    @Test func extractsSingleLineDefinition() {
        let text = "See [my link][ref] for details.\n\n[ref]: https://example.com \"Example\"\n"
        let definitions = PreviewLinkDefinitions.extract(from: text)
        #expect(definitions == ["[ref]: https://example.com \"Example\""])
    }

    @Test func extractsMultipleDefinitionsInDocumentOrder() {
        let text = """
        [one]: https://example.com/one
        Some paragraph text in between.
        [two]: https://example.com/two "Two"
        """
        let definitions = PreviewLinkDefinitions.extract(from: text)
        #expect(definitions == [
            "[one]: https://example.com/one",
            "[two]: https://example.com/two \"Two\"",
        ])
    }

    @Test func ignoresNonDefinitionLines() {
        let text = """
        # Heading
        A paragraph that mentions [a link](https://example.com) inline.
        - a list item
        > a blockquote
        """
        #expect(PreviewLinkDefinitions.extract(from: text).isEmpty)
    }

    @Test func allowsUpToThreeLeadingSpaces() {
        let text = "   [ref]: https://example.com"
        #expect(PreviewLinkDefinitions.extract(from: text) == ["   [ref]: https://example.com"])
    }

    @Test func fourLeadingSpacesIsNotADefinition() {
        // Four spaces is CommonMark's indented-code-block threshold, which
        // takes priority over a reference definition.
        let text = "    [ref]: https://example.com"
        #expect(PreviewLinkDefinitions.extract(from: text).isEmpty)
    }

    @Test func emptyTextReturnsNoDefinitions() {
        #expect(PreviewLinkDefinitions.extract(from: "").isEmpty)
    }
}
