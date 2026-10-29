import Foundation
@testable import Preview
import Testing
import Textual

@Suite("Preview resource rendering identity")
@MainActor
struct PreviewMarkupCacheTests {
    @Test(arguments: [
        "Ordinary **formatted** prose", "`![code](image.png)`", "\\![escaped](image.png)",
        "[ordinary link](relative.md)", "Unresolved ![image][missing]", "Inline $x^2$ math",
    ])
    func nonResourceTextKeepsItsIdentityAcrossResourceGenerations(_ source: String) {
        let parser = PreviewMarkupCache().parser(for: source, baseURL: nil)
        #expect(!parser.hasResourceReferences)
        #expect(parser.renderingIdentity(mathContentID: "", resourceLoadID: UUID())
            == parser.renderingIdentity(mathContentID: "", resourceLoadID: UUID()))
    }

    @Test(arguments: [
        "![image](image.png)",
        "![image][ref]\n\n[ref]: image.png",
        "![remote](https://example.invalid/a.png)",
    ])
    func imageTextStillReplacesItsAttachmentState(_ source: String) {
        let parser = PreviewMarkupCache().parser(for: source, baseURL: nil)
        #expect(parser.hasResourceReferences)
        #expect(parser.renderingIdentity(mathContentID: "", resourceLoadID: UUID())
            != parser.renderingIdentity(mathContentID: "", resourceLoadID: UUID()))
    }

    @Test func documentDefinitionsAreResolvedBeforeClassifyingTheBlock() throws {
        let cache = PreviewMarkupCache()
        let unresolved = cache.parser(for: "![image][ref]", baseURL: nil)
        let source = PreviewLinkDefinitionIndex(["[ref]: image.png"]).prefixed("![image][ref]")
        let resolved = cache.parser(for: source, baseURL: nil)
        #expect(!unresolved.hasResourceReferences)
        #expect(resolved.hasResourceReferences)
        let changed = cache.parser(
            for: PreviewLinkDefinitionIndex(["[ref]: other.png"]).prefixed("![image][ref]"), baseURL: nil
        )
        #expect(changed.hasResourceReferences)
        #expect(try resolved.attributedString(for: source) != changed.attributedString(for: changed.source))
    }

    @Test func relativeLinksReparseWhenTheDocumentBaseChanges() throws {
        let cache = PreviewMarkupCache()
        let source = "[related](related.md)"
        let first = cache.parser(for: source, baseURL: URL(fileURLWithPath: "/tmp/A/story.md"))
        let moved = cache.parser(for: source, baseURL: URL(fileURLWithPath: "/tmp/B/story.md"))
        #expect(first.renderingIdentity(mathContentID: "", resourceLoadID: nil)
            != moved.renderingIdentity(mathContentID: "", resourceLoadID: nil))
        #expect(try first.attributedString(for: source).runs.compactMap(\.link)
            != moved.attributedString(for: source).runs.compactMap(\.link))
    }

    @Test func cachedParsingIsIndependentOfResourceGenerationsAndReusedByTextual() throws {
        var parses = 0
        let cache = PreviewMarkupCache { source, baseURL in
            parses += 1
            return try PreviewMarkupParser(baseURL: baseURL, syntaxExtensions: [.math]).attributedString(for: source)
        }
        for _ in 0 ..< 10 {
            let parser = cache.parser(for: "unchanged", baseURL: nil)
            _ = parser.renderingIdentity(mathContentID: "", resourceLoadID: UUID())
            #expect(try String(parser.attributedString(for: "unchanged").characters) == "unchanged")
        }
        #expect(parses == 1)
        _ = cache.parser(for: "edited", baseURL: nil)
        #expect(parses == 2)
    }

    @Test func emojiURLsAndFailedParsingRetainConservativeResourceInvalidation() {
        let emoji = PreviewMarkupCache { _, _ in
            var text = AttributedString("emoji")
            text.textual.emojiURL = URL(fileURLWithPath: "/tmp/emoji.png")
            return text
        }.parser(for: "emoji", baseURL: nil)
        #expect(emoji.hasResourceReferences)
        let failed = PreviewMarkupCache { _, _ in throw CocoaError(.fileReadCorruptFile) }
            .parser(for: "unparsed", baseURL: nil)
        #expect(failed.hasResourceReferences)
        #expect(failed.renderingIdentity(mathContentID: "", resourceLoadID: UUID())
            != failed.renderingIdentity(mathContentID: "", resourceLoadID: UUID()))
    }

    @Test func resourceTextUsesTheOriginalParserInsteadOfCachedAttachmentOutput() throws {
        let source = "![image](image.png)"
        var classified = AttributedString("classification-only")
        classified.imageURL = URL(fileURLWithPath: "/tmp/classification.png")
        let parser = PreviewMarkupCache { _, _ in classified }.parser(for: source, baseURL: nil)
        let expected = try PreviewMarkupParser(baseURL: nil, syntaxExtensions: [.math]).attributedString(for: source)
        #expect(parser.hasResourceReferences)
        #expect(try parser.attributedString(for: source) == expected)
        #expect(try parser.attributedString(for: source) != classified)
    }

    @Test func mathContentStillChangesRenderingIdentity() {
        let parser = PreviewMarkupCache().parser(for: "Inline $x$", baseURL: nil)
        #expect(parser.renderingIdentity(mathContentID: "$x$", resourceLoadID: UUID())
            != parser.renderingIdentity(mathContentID: "$y$", resourceLoadID: UUID()))
    }
}
