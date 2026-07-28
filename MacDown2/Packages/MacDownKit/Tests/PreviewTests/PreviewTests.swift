@testable import FileCore
import Foundation
@testable import MarkdownEngine
@testable import Preview
import Testing
import Themes

@Test func moduleLoads() {
    #expect(PreviewModule.moduleName == "Preview")
}

@Suite("PreviewRouter")
struct PreviewRouterTests {
    @Test func markdownRendersAsMarkdown() {
        let formats = FileFormatRegistry.defaultFormats
        let markdown = formats.first { $0.id == "markdown" }
        #expect(markdown != nil)
        #expect(PreviewRouter.previewKind(for: markdown ?? plaintextFallback()) == .markdown)
    }

    @Test func htmlRendersAsHTML() {
        let formats = FileFormatRegistry.defaultFormats
        let html = formats.first { $0.id == "html" }
        #expect(html != nil)
        #expect(PreviewRouter.previewKind(for: html ?? plaintextFallback()) == .html)
    }

    @Test func jsonPreviewIsToggleable() {
        let formats = FileFormatRegistry.defaultFormats
        let json = formats.first { $0.id == "json" }
        #expect(json != nil)
        #expect(PreviewRouter.previewKind(for: json ?? plaintextFallback()) == .none)
    }

    @Test func plaintextHasNoPreview() {
        let formats = FileFormatRegistry.defaultFormats
        let plaintext = formats.first { $0.id == "plaintext" }
        #expect(plaintext != nil)
        #expect(PreviewRouter.previewKind(for: plaintext ?? plaintextFallback()) == .none)
    }
}

private func plaintextFallback() -> FileFormat {
    FileFormat(
        id: "plaintext",
        name: "Plain Text",
        utType: .plainText,
        extensions: ["txt"]
    )
}

@Suite("PreviewSecurity")
struct PreviewSecurityTests {
    @Test func injectsCSPIntoExistingHead() {
        let html = "<html><head><title>t</title></head><body>hi</body></html>"
        let out = PreviewSecurity.hardenedHTMLDocument(from: html)
        #expect(out.contains("Content-Security-Policy"))
        #expect(out.contains("default-src 'none'"))
        // The CSP must appear before the document's own <title>.
        let csp = out.range(of: "Content-Security-Policy")
        let title = out.range(of: "<title>")
        #expect(csp != nil)
        #expect(title != nil)
        if let csp, let title {
            #expect(csp.lowerBound < title.lowerBound)
        }
    }

    @Test func addsHeadWhenOnlyHTMLTagPresent() {
        let html = "<html><body>content</body></html>"
        let out = PreviewSecurity.hardenedHTMLDocument(from: html)
        #expect(out.contains("<html><head>"))
        #expect(out.contains("Content-Security-Policy"))
        #expect(out.contains("<body>content</body>"))
    }

    @Test func wrapsBareFragment() {
        let html = "<p>hello</p>"
        let out = PreviewSecurity.hardenedHTMLDocument(from: html)
        #expect(out.hasPrefix("<!DOCTYPE html>"))
        #expect(out.contains("Content-Security-Policy"))
        #expect(out.contains("<p>hello</p>"))
    }

    @Test func doesNotMatchHeaderTag() {
        // <header> must not be mistaken for <head>; a real <head> is added
        // after <html> instead.
        let html = "<html><body><header>menu</header></body></html>"
        let out = PreviewSecurity.hardenedHTMLDocument(from: html)
        #expect(out.contains("<html><head>"))
        #expect(out.contains("<header>menu</header>"))
        #expect(out.contains("Content-Security-Policy"))
    }

    @Test func matchesHeadWithAttributes() {
        let html = "<html><head class=\"x\"><title>t</title></head><body>hi</body></html>"
        let out = PreviewSecurity.hardenedHTMLDocument(from: html)
        // Injected right after the opening <head ...> tag.
        #expect(out.contains("<head class=\"x\"><meta http-equiv=\"Content-Security-Policy\""))
    }
}

@Suite("PreviewBlock")
struct PreviewBlockTests {
    @Test func extractsBlockSourceFromOriginalText() {
        let text = "# Hello\n\nFirst paragraph.\n\nSecond paragraph."
        let blocks = [
            MarkdownBlock(kind: .heading(level: 1), lineRange: 1 ... 1),
            MarkdownBlock(kind: .paragraph, lineRange: 3 ... 3),
            MarkdownBlock(kind: .paragraph, lineRange: 5 ... 5),
        ]
        let document = PreviewFixtures.documentWithBlocks(text: text, blocks: blocks)
        let previewBlocks = PreviewBlock.blocks(from: document, text: text)

        #expect(previewBlocks.count == 3)
        #expect(previewBlocks[0].source == "# Hello")
        #expect(previewBlocks[1].source == "First paragraph.")
        #expect(previewBlocks[2].source == "Second paragraph.")
    }

    @Test func blockSourceExcludesLineTerminators() {
        // SourceMap ranges stop before the terminating newline, so block
        // sources do not include it.
        let text = "# Hello\n\nBody\n"
        let blocks = [
            MarkdownBlock(kind: .heading(level: 1), lineRange: 1 ... 1),
            MarkdownBlock(kind: .paragraph, lineRange: 3 ... 3),
        ]
        let document = PreviewFixtures.documentWithBlocks(text: text, blocks: blocks)
        let previewBlocks = PreviewBlock.blocks(from: document, text: text)

        #expect(previewBlocks[0].source == "# Hello")
        #expect(previewBlocks[1].source == "Body")
    }

    @Test func blockIDsAreStableAcrossRebuilds() {
        // Preview blocks derive their identity from content and position so
        // SwiftUI view identity (and the scroll-sync frame lookup) survives
        // re-evaluation. Random IDs would churn `ForEach` on every pass.
        let text = "# Hello\n\nFirst paragraph.\n\nSecond paragraph."
        let blocks = [
            MarkdownBlock(kind: .heading(level: 1), lineRange: 1 ... 1),
            MarkdownBlock(kind: .paragraph, lineRange: 3 ... 3),
            MarkdownBlock(kind: .paragraph, lineRange: 5 ... 5),
        ]
        let document = PreviewFixtures.documentWithBlocks(text: text, blocks: blocks)

        let first = PreviewBlock.blocks(from: document, text: text)
        let second = PreviewBlock.blocks(from: document, text: text)

        #expect(first == second)
        #expect(Set(first.map(\.id)).count == first.count)
    }
}

@Suite("ScrollSyncMap")
struct ScrollSyncMapTests {
    @Test func mapsLinesToBlockIndices() {
        let blocks = [
            PreviewBlock(kind: .heading(level: 1), source: "# H", lineRange: 1 ... 1),
            PreviewBlock(kind: .paragraph, source: "p1", lineRange: 3 ... 3),
            PreviewBlock(kind: .paragraph, source: "p2", lineRange: 5 ... 5),
        ]
        let map = ScrollSyncMap(blocks: blocks)

        #expect(map.blockIndex(forLine: 1) == 0)
        #expect(map.blockIndex(forLine: 3) == 1)
        #expect(map.blockIndex(forLine: 5) == 2)
    }

    @Test func fallsBackToNearestBlockForBlankLines() {
        let blocks = [
            PreviewBlock(kind: .heading(level: 1), source: "# H", lineRange: 1 ... 1),
            PreviewBlock(kind: .paragraph, source: "p1", lineRange: 3 ... 3),
        ]
        let map = ScrollSyncMap(blocks: blocks)

        #expect(map.blockIndex(forLine: 2) == 0)
        #expect(map.blockIndex(forLine: 4) == 1)
    }

    @Test func lineForBlockIndexReturnsFirstLine() {
        let blocks = [
            PreviewBlock(kind: .heading(level: 1), source: "# H", lineRange: 1 ... 1),
            PreviewBlock(kind: .paragraph, source: "p1", lineRange: 3 ... 5),
        ]
        let map = ScrollSyncMap(blocks: blocks)

        #expect(map.line(forBlockIndex: 1) == 3)
    }
}

@Suite("ScrollSyncController")
@MainActor
struct ScrollSyncControllerTests {
    @Test func previewFractionForFirstLineIsZero() {
        let blocks = [
            PreviewBlock(kind: .heading(level: 1), source: "# H", lineRange: 1 ... 1),
            PreviewBlock(kind: .paragraph, source: "p1", lineRange: 3 ... 3),
        ]
        let controller = ScrollSyncController(
            map: ScrollSyncMap(blocks: blocks),
            blockHeights: [0: 10, 1: 20]
        )

        #expect(controller.previewFraction(forLine: 1) == 0)
    }

    @Test func previewFractionAtSecondBlockStart() {
        let blocks = [
            PreviewBlock(kind: .heading(level: 1), source: "# H", lineRange: 1 ... 1),
            PreviewBlock(kind: .paragraph, source: "p1", lineRange: 3 ... 3),
        ]
        let controller = ScrollSyncController(
            map: ScrollSyncMap(blocks: blocks),
            blockHeights: [0: 10, 1: 20]
        )

        #expect(controller.previewFraction(forLine: 3) == 10.0 / 30.0)
    }

    @Test func lineForPreviewFractionRoundTrips() {
        let blocks = [
            PreviewBlock(kind: .heading(level: 1), source: "# H", lineRange: 1 ... 1),
            PreviewBlock(kind: .paragraph, source: "p1", lineRange: 3 ... 5),
        ]
        let controller = ScrollSyncController(
            map: ScrollSyncMap(blocks: blocks),
            blockHeights: [0: 10, 1: 30]
        )

        let fraction = controller.previewFraction(forLine: 4)
        #expect(fraction != nil)
        #expect(controller.line(forPreviewFraction: fraction ?? 0) == 4)
    }

    @Test func emptyMapReturnsNoFraction() {
        let controller = ScrollSyncController()
        #expect(controller.previewFraction(forLine: 1) == nil)
        #expect(controller.line(forPreviewFraction: 0.5) == nil)
    }

    @Test func editorScrollPublishesPreviewFraction() {
        let blocks = [
            PreviewBlock(kind: .heading(level: 1), source: "# H", lineRange: 1 ... 1),
            PreviewBlock(kind: .paragraph, source: "p1", lineRange: 3 ... 3),
        ]
        let controller = ScrollSyncController(
            map: ScrollSyncMap(blocks: blocks),
            blockHeights: [0: 10, 1: 20]
        )

        controller.editorDidScroll(toLine: 3)

        #expect(controller.targetPreviewFraction == 10.0 / 30.0)
    }

    @Test func previewScrollPublishesTargetSourceLine() {
        let blocks = [
            PreviewBlock(kind: .heading(level: 1), source: "# H", lineRange: 1 ... 1),
            PreviewBlock(kind: .paragraph, source: "p1", lineRange: 3 ... 3),
        ]
        let controller = ScrollSyncController(
            map: ScrollSyncMap(blocks: blocks),
            blockHeights: [0: 10, 1: 20]
        )

        // Content offset 10 is exactly the start of block 1 (line 3).
        controller.previewContentOffsetDidChange(10)

        #expect(controller.targetSourceLine == 3)
    }

    // Regression: without echo suppression, an editor-driven preview scroll
    // gets reported back by the preview's own scroll notification, which
    // would re-target the editor and bounce indefinitely.
    @Test func editorDrivenPreviewScrollIsNotEchoedBackToEditor() {
        let blocks = [
            PreviewBlock(kind: .heading(level: 1), source: "# H", lineRange: 1 ... 1),
            PreviewBlock(kind: .paragraph, source: "p1", lineRange: 3 ... 3),
        ]
        let controller = ScrollSyncController(
            map: ScrollSyncMap(blocks: blocks),
            blockHeights: [0: 10, 1: 20]
        )

        controller.editorDidScroll(toLine: 3)
        #expect(controller.targetPreviewFraction != nil)
        controller.targetPreviewFraction = nil

        // The preview reports the position it was just told to adopt (block 1
        // starts at content offset 10).
        controller.previewContentOffsetDidChange(10)

        #expect(controller.targetSourceLine == nil, "Echo of the editor-driven scroll must not bounce back")
    }

    /// Symmetric case for the reverse direction.
    @Test func previewDrivenEditorScrollIsNotEchoedBackToPreview() {
        let blocks = [
            PreviewBlock(kind: .heading(level: 1), source: "# H", lineRange: 1 ... 1),
            PreviewBlock(kind: .paragraph, source: "p1", lineRange: 3 ... 3),
        ]
        let controller = ScrollSyncController(
            map: ScrollSyncMap(blocks: blocks),
            blockHeights: [0: 10, 1: 20]
        )

        controller.previewContentOffsetDidChange(10)
        #expect(controller.targetSourceLine != nil)
        controller.targetSourceLine = nil

        // The editor reports the line it was just told to adopt.
        controller.editorDidScroll(toLine: 3)

        #expect(controller.targetPreviewFraction == nil, "Echo of the preview-driven scroll must not bounce back")
    }

    @Test func genuineFollowUpScrollAfterEchoIsNotSuppressed() {
        let blocks = [
            PreviewBlock(kind: .heading(level: 1), source: "# H", lineRange: 1 ... 1),
            PreviewBlock(kind: .paragraph, source: "p1", lineRange: 3 ... 3),
        ]
        let controller = ScrollSyncController(
            map: ScrollSyncMap(blocks: blocks),
            blockHeights: [0: 10, 1: 20]
        )

        controller.editorDidScroll(toLine: 3)
        controller.targetPreviewFraction = nil
        controller.previewContentOffsetDidChange(10) // echo, swallowed
        #expect(controller.targetSourceLine == nil)

        // A real user scroll of the preview back to the top must still work
        // after the echo was swallowed once.
        controller.previewContentOffsetDidChange(0)
        #expect(controller.targetSourceLine == 1)
    }
}

@Suite("PreviewLinkResolver")
struct PreviewLinkResolverTests {
    @Test func leavesAbsoluteURLUnchanged() throws {
        let resolver = PreviewLinkResolver(baseURL: URL(string: "https://example.com/page.md"))
        let url = try #require(URL(string: "https://other.com/doc.md"))
        #expect(resolver.resolve(url) == url)
    }

    @Test func resolvesRelativeURLAgainstBaseURL() throws {
        let base = URL(string: "https://example.com/page.md")
        let resolver = PreviewLinkResolver(baseURL: base)
        let url = try #require(URL(string: "other.md"))
        let resolved = resolver.resolve(url)
        #expect(resolved.absoluteString == "https://example.com/other.md")
    }

    @Test func returnsOriginalWhenNoBaseURL() throws {
        let resolver = PreviewLinkResolver()
        let url = try #require(URL(string: "other.md"))
        #expect(resolver.resolve(url) == url)
    }
}

@Suite("PreviewTheme")
struct PreviewThemeTests {
    @Test func derivesFromEditorTheme() {
        let theme = BundledThemes.light
        let preview = PreviewTheme(theme: theme)

        #expect(preview.background == theme.chrome.background)
        #expect(preview.foreground == theme.chrome.foreground)
    }

    @Test func defaultThemeIsDifferentForLightAndDark() {
        let light = PreviewTheme.default(for: .light)
        let dark = PreviewTheme.default(for: .dark)

        #expect(light.background != dark.background)
    }
}
