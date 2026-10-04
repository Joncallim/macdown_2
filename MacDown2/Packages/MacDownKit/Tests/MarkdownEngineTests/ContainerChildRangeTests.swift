import Foundation
@testable import MarkdownEngine
import Testing

/// Review pass 6: swift-markdown reports an unterminated fence inside a list item or quote as running on through the
/// following item or paragraph, so a child block's line range extended past its parent's (11,677 violations in 30,000
/// fuzzed documents), and the export treated the next item's `$x$` as being inside that code block.
struct ContainerChildRangeTests {
    private func violations(in blocks: [MarkdownBlock], parent: ClosedRange<Int>? = nil) -> [String] {
        blocks.flatMap { block -> [String] in
            var found: [String] = []
            if let parent,
               block.lineRange.lowerBound < parent.lowerBound || block.lineRange.upperBound > parent.upperBound {
                found.append("\(block.kind) \(block.lineRange) escapes \(parent)")
            }
            return found + violations(in: block.children, parent: block.lineRange)
        }
    }

    @Test func anUnterminatedFenceInAListItemStopsAtTheItem() async throws {
        let document = try await ParseEngine().parse("- ```js\n  code\n- item $x$\n", revision: 1)

        #expect(violations(in: document.blocks).isEmpty)
        let item = try #require(document.blocks.first?.children.first)
        #expect(item.lineRange == 1 ... 2)
        #expect(item.children.first?.lineRange.upperBound ?? 99 <= 2)
    }

    @Test func anUnterminatedFenceInAQuoteStopsAtTheQuote() async throws {
        let document = try await ParseEngine().parse("> ```\n> text\n\nafter\n", revision: 1)

        #expect(violations(in: document.blocks).isEmpty)
    }

    @Test func childRangesStayInsideTheirParentsAcrossGeneratedDocuments() async throws {
        let fragments = [
            "- item", "  - nested", "> quote", "> > deep", "```", "```js", "~~~", "text", "", "1. one", "---",
            "# head", "| a | b |", "|---|---|", "    indented", "<div>",
        ]
        var state: UInt64 = 7
        func next(_ bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 33) % UInt64(bound))
        }
        let engine = ParseEngine()
        for _ in 0 ..< 400 {
            let text = (0 ..< (3 + next(8))).map { _ in fragments[next(fragments.count)] }.joined(separator: "\n")
            let document = try await engine.parse(text, revision: 1)
            #expect(violations(in: document.blocks).isEmpty, "\(text.debugDescription)")
        }
    }
}
