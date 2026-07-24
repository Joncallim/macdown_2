import Foundation
@testable import MarkdownEngine
import Testing

struct BlockConversionTests {
    private let engine = ParseEngine()

    @Test func moduleLoads() {
        #expect(MarkdownEngine.moduleName == "MarkdownEngine")
    }

    @Test func parsesHeadings() async throws {
        let document = try await engine.parse(Fixtures.headingCorpus, revision: 1)

        #expect(document.blocks.count == 3)
        #expect(document.blocks[0].kind == .heading(level: 1))
        #expect(document.blocks[1].kind == .heading(level: 2))
        #expect(document.blocks[2].kind == .heading(level: 3))
    }

    @Test func headingLineRangesAreOriginalSourceLines() async throws {
        let document = try await engine.parse(Fixtures.headingCorpus, revision: 1)

        #expect(document.blocks[0].lineRange == 1 ... 1)
        #expect(document.blocks[1].lineRange == 2 ... 2)
        #expect(document.blocks[2].lineRange == 3 ... 3)
    }

    @Test func parsesFencedAndIndentedCodeBlocks() async throws {
        let document = try await engine.parse(Fixtures.codeBlockCorpus, revision: 1)

        let codeBlocks = document.blocks.filter(\.kind.isCodeBlock)
        #expect(codeBlocks.count == 3)

        #expect(codeBlocks[0].kind == .codeBlock(language: "swift"))
        #expect(codeBlocks[1].kind == .codeBlock(language: nil))
        #expect(codeBlocks[2].kind == .codeBlock(language: nil))
    }

    @Test func parsesOrderedAndUnorderedLists() async throws {
        let document = try await engine.parse(Fixtures.listCorpus, revision: 1)

        let topLevelLists = document.blocks.filter(\.kind.isList)
        #expect(topLevelLists.count == 2)
        #expect(topLevelLists[0].kind == .orderedList(startIndex: 1))
        #expect(topLevelLists[1].kind == .unorderedList)
    }

    @Test func listItemsAreNestedChildren() async throws {
        let document = try await engine.parse(Fixtures.listCorpus, revision: 1)

        let orderedList = document.blocks.first { $0.kind == .orderedList(startIndex: 1) }
        let orderedItems = orderedList?.children.filter(\.kind.isListItem)
        #expect(orderedItems?.count == 3)

        let nestedList = orderedItems?[1].children.first { $0.kind == .unorderedList }
        #expect(nestedList != nil)
        #expect(nestedList?.children.count == 2)
    }

    @Test func parsesTaskLists() async throws {
        let document = try await engine.parse(Fixtures.taskListCorpus, revision: 1)

        let list = document.blocks.first { $0.kind == .unorderedList }
        let items = list?.children.filter(\.kind.isListItem)

        #expect(items?.count == 2)
        #expect(items?[0].kind == .listItem(taskState: .checked))
        #expect(items?[1].kind == .listItem(taskState: .unchecked))
    }

    @Test func parsesBlockQuote() async throws {
        let document = try await engine.parse(Fixtures.blockQuoteCorpus, revision: 1)

        #expect(document.blocks.count == 1)
        #expect(document.blocks[0].kind == .blockQuote)
    }

    @Test func blockQuoteChildrenAreBlocks() async throws {
        let document = try await engine.parse(Fixtures.blockQuoteCorpus, revision: 1)

        let quote = document.blocks[0]
        let paragraph = quote.children.first { $0.kind == .paragraph }
        let heading = quote.children.first { $0.kind == .heading(level: 2) }

        #expect(paragraph != nil)
        #expect(heading != nil)
    }

    @Test func parsesTableWithColumnCount() async throws {
        let document = try await engine.parse(Fixtures.tableCorpus, revision: 1)

        let table = document.blocks.first { $0.kind.isTable }
        #expect(table != nil)
        #expect(table?.kind == .table(columnCount: 3))
    }

    @Test func parsesThematicBreaks() async throws {
        let document = try await engine.parse(Fixtures.thematicBreakCorpus, revision: 1)

        let breaks = document.blocks.filter { $0.kind == .thematicBreak }
        #expect(breaks.count == 3)
    }

    @Test func parsesHTMLBlock() async throws {
        let document = try await engine.parse(Fixtures.htmlBlockCorpus, revision: 1)

        #expect(document.blocks.contains(where: { $0.kind == .htmlBlock }))
    }

    @Test func inlineMarkupProducesParagraphBlocks() async throws {
        let text = "This has **bold** and `code`.\n"
        let document = try await engine.parse(text, revision: 1)

        #expect(document.blocks.count == 1)
        #expect(document.blocks[0].kind == .paragraph)
    }

    @Test func autolinkAndStrikethroughDoNotCrash() async throws {
        let text = """
        Visit https://example.com.

        ~~deleted~~
        """
        let document = try await engine.parse(text, revision: 1)

        #expect(document.blocks.count == 2)
        #expect(document.blocks.allSatisfy { $0.kind == .paragraph })
    }

    @Test func blockAtLineReturnsDeepestBlock() async throws {
        let document = try await engine.parse(Fixtures.listCorpus, revision: 1)

        let block = document.block(atLine: 3)
        #expect(block != nil)
        #expect(block?.kind.isListItem == true)
    }

    @Test func blockAtLineBetweenBlocksReturnsNil() async throws {
        let text = "# A\n\n# B\n"
        let document = try await engine.parse(text, revision: 1)

        #expect(document.block(atLine: 2) == nil)
    }

    @Test func blockAtLineInFrontMatterReturnsNil() async throws {
        let document = try await engine.parse(Fixtures.validFrontMatter, revision: 1)

        #expect(document.block(atLine: 1) == nil)
        #expect(document.block(atLine: 8) == nil)
    }

    @Test func unknownBlockMapsToCustom() async throws {
        // Block directives are supported by swift-markdown but not mapped
        // explicitly in BlockKind, so they exercise the custom escape hatch.
        let text = """
        @MyBlock {
        Content
        }
        """
        let document = try await engine.parse(text, revision: 1)

        let custom = document.blocks.first { $0.kind.isCustom }
        #expect(custom != nil)
        #expect(custom?.children.isEmpty == false)
    }

    @Test func footnotesAreNotSupportedByParser() async throws {
        // swift-markdown 0.8.0 does not parse footnotes; the reference and
        // definition remain plain text inside paragraph blocks.
        let text = """
        Here is a footnote reference[^1].

        [^1]: This is the footnote.
        """
        let document = try await engine.parse(text, revision: 1)

        #expect(document.blocks.contains(where: { $0.kind == .footnoteDefinition(label: "1") }) == false)
        #expect(document.blocks.allSatisfy { $0.kind == .paragraph })
    }
}

private extension BlockKind {
    var isCodeBlock: Bool {
        if case .codeBlock = self {
            return true
        }
        return false
    }

    var isList: Bool {
        switch self {
        case .orderedList, .unorderedList:
            true
        default:
            false
        }
    }

    var isListItem: Bool {
        if case .listItem = self {
            return true
        }
        return false
    }

    var isTable: Bool {
        if case .table = self {
            return true
        }
        return false
    }

    var isCustom: Bool {
        if case .custom = self {
            return true
        }
        return false
    }
}
