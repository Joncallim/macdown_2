import Foundation
@testable import MarkdownEngine
import Testing

/// Review pass 5: Yams force-unwraps the scalar construction of every mapping key, so front matter whose key is a
/// sequence, a mapping or a link-reference-looking flow sequence terminated the whole process on open.
struct YAMLNonScalarKeyTests {
    @Test(arguments: [
        "[ref]: http://x",
        "? [a, b]\n: c",
        "{a: b}: c",
        "outer:\n  [nested]: value",
        "list:\n  - [k]: v",
    ])
    func aNonScalarKeyIsRejectedInsteadOfCrashing(_ yaml: String) async throws {
        let document = try await ParseEngine().parse("---\n\(yaml)\n---\n# Title\n", revision: 1)

        #expect(document.frontMatter?.values == nil)
        #expect(document.headings.count == 1)
    }

    @Test func ordinaryFrontMatterStillParses() async throws {
        let text = "---\ntitle: Hello\ntags: [a, b]\nmeta:\n  nested: 1\n---\n# T\n"
        let document = try await ParseEngine().parse(text, revision: 1)

        #expect(document.frontMatter?.values?["title"] == .string("Hello"))
        #expect(document.frontMatter?.values?["meta"] == .dictionary(["nested": .int(1)]))
    }

    @Test func aDeeplyNestedDocumentIsWalkedWithoutRecursion() async throws {
        let depth = 3000
        let yaml = "a: " + String(repeating: "[", count: depth) + String(repeating: "]", count: depth)
        let document = try await ParseEngine().parse("---\n\(yaml)\n---\n# T\n", revision: 1)

        #expect(document.headings.count == 1)
    }
}
