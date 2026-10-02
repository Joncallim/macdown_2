import Foundation
@testable import MarkdownEngine
import Testing

/// Review pass 1 (P0): the parse recursed once per nesting level on a small
/// cooperative-thread stack, so a few KB of nested input killed the process
/// (and again on every relaunch that restored the document).
struct ParseDeepNestingTests {
    @Test func deeplyNestedBlockQuotesDoNotCrash() async throws {
        let text = String(repeating: ">", count: 20000) + " x\n"
        let document = try await ParseEngine().parse(text, revision: 1)
        #expect(!document.blocks.isEmpty)
    }

    @Test func deeplyNestedListsDoNotCrash() async throws {
        var text = ""
        for depth in 0 ..< 3000 {
            text += String(repeating: " ", count: depth * 2) + "- item\n"
        }
        let document = try await ParseEngine().parse(text, revision: 1)
        #expect(!document.blocks.isEmpty)
    }

    @Test func deeplyNestedEmphasisDoesNotCrash() async throws {
        let text = String(repeating: "*a ", count: 5000) + String(repeating: "a* ", count: 5000) + "\n"
        let document = try await ParseEngine().parse(text, revision: 1)
        #expect(!document.blocks.isEmpty)
    }

    @Test func deeplyNestedYAMLFlowFrontMatterDoesNotCrash() async throws {
        let nested = String(repeating: "[", count: 5000) + String(repeating: "]", count: 5000)
        let text = "---\na: \(nested)\n---\n# Title\n"
        let document = try await ParseEngine().parse(text, revision: 1)
        #expect(document.headings.count == 1)
    }
}
