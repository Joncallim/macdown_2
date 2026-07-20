@testable import FileCore
@testable import Preview
import Testing

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
