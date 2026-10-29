import Foundation
@testable import Preview
import Testing

/// Review pass 1: a clicked Preview link went straight to Launch Services.
struct PreviewLinkActionTests {
    private func action(_ string: String) -> PreviewLinkResolver.LinkAction {
        guard let url = URL(string: string) else { return .ignore }
        return PreviewLinkResolver.action(for: url)
    }

    @Test func webAndMailLinksOpen() {
        #expect(action("https://example.com/a") == .open)
        #expect(action("HTTP://example.com") == .open)
        #expect(action("mailto:a@example.com") == .open)
    }

    @Test func localDocumentsOpenInTheAppButOtherLocalFilesOnlyRevealInFinder() {
        #expect(action("file:///Users/me/notes/other.md") ==
            .openInApp(URL(fileURLWithPath: "/Users/me/notes/other.md")))
        #expect(action("file:///Users/me/notes/plain.TXT") ==
            .openInApp(URL(fileURLWithPath: "/Users/me/notes/plain.TXT")))
        #expect(action("file:///Users/me/scripts/setup.command") == .reveal)
        #expect(action("file:///Applications/Foo.app") == .reveal)
        #expect(action("file:///Users/me/run.sh") == .reveal)
    }

    @Test func everyOtherSchemeIsIgnored() {
        for link in [
            "ssh://host",
            "vnc://host",
            "smb://host/share",
            "x-apple.systempreferences:",
            "javascript:alert(1)",
            "data:text/html,hi",
            "tel:123",
            "itms-apps://x",
        ] {
            #expect(action(link) == .ignore, "\(link)")
        }
    }

    @Test func aFragmentOrQueryIsDroppedWhenOpeningADocument() {
        #expect(action("file:///Users/me/notes/other.md#section") ==
            .openInApp(URL(fileURLWithPath: "/Users/me/notes/other.md")))
    }

    @Test(arguments: ["/tmp/A/story.md", "/tmp/B/story.md"])
    @MainActor
    func parserRelativeDocumentLinksKeepTheirAbsoluteDestination(_ path: String) throws {
        let base = URL(fileURLWithPath: path)
        let parsed = try PreviewMarkupParser(baseURL: base)
            .attributedString(for: "[related](related.md#section)")
        let link = try #require(parsed.runs.compactMap(\.link).first)
        let resolved = PreviewLinkResolver(baseURL: base).resolve(link)
        #expect(resolved.baseURL == nil, "File opening requires a self-contained URL")
        #expect(PreviewLinkResolver.action(for: resolved, currentDocument: base)
            == .openInApp(base.deletingLastPathComponent().appendingPathComponent("related.md")))
    }

    @Test @MainActor func parserRelativeLinksKeepAnchorAndExecutableSafetyRules() throws {
        let base = URL(fileURLWithPath: "/tmp/preview-actions/story.md")
        let resolver = PreviewLinkResolver(baseURL: base)
        for (target, expected) in [("#heading", PreviewLinkResolver.LinkAction.ignore), ("setup.command", .reveal)] {
            let parsed = try PreviewMarkupParser(baseURL: base).attributedString(for: "[target](\(target))")
            let link = try #require(parsed.runs.compactMap(\.link).first)
            #expect(PreviewLinkResolver.action(for: resolver.resolve(link), currentDocument: base) == expected)
        }
    }

    @Test func aSameDocumentAnchorDoesNotReopenTheDocument() throws {
        let current = URL(fileURLWithPath: "/Users/me/notes/this.md")
        let anchor = try #require(URL(string: "file:///Users/me/notes/this.md#heading"))
        #expect(PreviewLinkResolver.action(for: anchor, currentDocument: current) == .ignore)
    }
}
