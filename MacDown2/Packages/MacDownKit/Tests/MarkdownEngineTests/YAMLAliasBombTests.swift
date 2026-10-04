import Foundation
@testable import MarkdownEngine
import Testing

/// Review pass 1: tiny YAML front matter with nested aliases expanded
/// exponentially and hung the shared parse actor (and exhausted memory).
struct YAMLAliasBombTests {
    private func bomb(levels: Int, fanOut: Int) -> String {
        var lines = ["a0: &a0 [\"lol\",\"lol\",\"lol\",\"lol\",\"lol\",\"lol\",\"lol\",\"lol\",\"lol\"]"]
        for level in 1 ..< levels {
            let refs = Array(repeating: "*a\(level - 1)", count: fanOut).joined(separator: ",")
            lines.append("a\(level): &a\(level) [\(refs)]")
        }
        return "---\n" + lines.joined(separator: "\n") + "\n---\n# Title\n"
    }

    @Test func anAliasBombIsNotExpandedAndTheDocumentStillParses() async throws {
        let start = ContinuousClock.now
        let document = try await ParseEngine().parse(bomb(levels: 9, fanOut: 9), revision: 1)

        #expect(document.frontMatter?.values == nil)
        #expect(document.headings.count == 1)
        #expect(ContinuousClock.now - start < .seconds(20))
    }

    @Test func ordinaryAnchorsAndAliasesStillParse() async throws {
        let text = "---\nbase: &base {x: 1}\nuse: *base\nname: Hello\n---\n# T\n"
        let document = try await ParseEngine().parse(text, revision: 1)

        #expect(document.frontMatter?.values?["name"] == .string("Hello"))
    }

    @Test func anchorNamesThatDoNotStartWithALetterCountTowardTheBudget() {
        let refs = (0 ..< 20).map { _ in "*-a0" }.joined(separator: ",")
        #expect(ParseEngine.exceedsYAMLAliasBudget("a0: &-a0 [x]\nb: [\(refs)]"))
        let dotted = (0 ..< 20).map { _ in "*.a" }.joined(separator: ",")
        #expect(ParseEngine.exceedsYAMLAliasBudget("a: &.a [x]\nb: [\(dotted)]"))
    }

    @Test func aDashAnchoredBombIsNotExpanded() async throws {
        var lines = ["a0: &-a0 [\"lol\",\"lol\",\"lol\",\"lol\",\"lol\",\"lol\",\"lol\",\"lol\",\"lol\"]"]
        for level in 1 ..< 9 {
            let refs = Array(repeating: "*-a\(level - 1)", count: 9).joined(separator: ",")
            lines.append("a\(level): &-a\(level) [\(refs)]")
        }
        let start = ContinuousClock.now
        let document = try await ParseEngine().parse(
            "---\n" + lines.joined(separator: "\n") + "\n---\n# T\n",
            revision: 1
        )

        #expect(document.frontMatter?.values == nil)
        #expect(ContinuousClock.now - start < .seconds(20))
    }

    /// Review pass 6: 16 aliases (the count budget) can still double eight times, so a ~20 KB front matter expanded
    /// 256x (324 MB, seconds) on every parse. The expanded size is budgeted too.
    @Test func aDoublingChainWithinTheAliasCountIsStillRejected() async throws {
        let base = Array(repeating: "1", count: 10000).joined(separator: ",")
        var lines = ["a0: &a0 [\(base)]"]
        for level in 1 ... 8 {
            lines.append("a\(level): &a\(level) [*a\(level - 1),*a\(level - 1)]")
        }
        let text = "---\n" + lines.joined(separator: "\n") + "\n---\n# Title\n"
        let start = ContinuousClock.now

        let document = try await ParseEngine().parse(text, revision: 1)

        #expect(document.frontMatter?.values == nil)
        #expect(document.headings.count == 1)
        #expect(ContinuousClock.now - start < .seconds(5))
    }

    @Test func modestAnchorReuseStillParses() async throws {
        let text = "---\ndefaults: &d {a: 1, b: 2}\nx:\n  <<: *d\ny:\n  <<: *d\ntitle: T\n---\n# H\n"
        let document = try await ParseEngine().parse(text, revision: 1)

        #expect(document.frontMatter?.values?["title"] == .string("T"))
    }
}
