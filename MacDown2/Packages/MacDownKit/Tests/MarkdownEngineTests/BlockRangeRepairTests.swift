import Foundation
@testable import MarkdownEngine
import Testing

/// Review pass 1: swift-markdown reports wrong ranges for a paragraph directly
/// before a table and for a setext heading directly before another block; the
/// resulting overlaps duplicated content in Preview and broke scroll sync.
struct BlockRangeRepairTests {
    private func ranges(_ text: String) async throws -> [String] {
        try await ParseEngine().parse(text, revision: 1).blocks.map { block in
            let name = switch block.kind {
            case .paragraph: "p"
            case .table: "table"
            case .heading: "h"
            case .codeBlock: "code"
            default: "other"
            }
            return "\(name) \(block.lineRange.lowerBound)...\(block.lineRange.upperBound)"
        }
    }

    @Test func aParagraphDirectlyBeforeATableKeepsItsOwnLines() async throws {
        let result = try await ranges("Here is a table:\n| a | b |\n|---|---|\n| 1 | 2 |\n\nAfter.\n")
        #expect(result == ["p 1...1", "table 2...4", "p 6...6"])
    }

    @Test func aSetextHeadingDirectlyBeforeAParagraphEndsAtItsUnderline() async throws {
        #expect(try await ranges("Title\n=====\nBody text here.\n") == ["h 1...2", "p 3...3"])
        #expect(try await ranges("Title\n-----\nBody\n") == ["h 1...2", "p 3...3"])
    }

    @Test func rangesAreUnchangedWhenSwiftMarkdownGetsThemRight() async throws {
        #expect(try await ranges("Title\n=====\n\nBody.\n") == ["h 1...2", "p 4...4"])
        #expect(try await ranges("para\n```swift\ncode\n```\ntail\n") == ["p 1...1", "code 2...4", "p 5...5"])
    }

    @Test func siblingRangesNeverOverlapAfterFrontMatter() async throws {
        let result = try await ranges("---\ntitle: x\n---\nIntro:\n| a |\n|---|\n| 1 |\n\nTail\n")
        #expect(result == ["p 4...4", "table 5...7", "p 9...9"])
    }
}
