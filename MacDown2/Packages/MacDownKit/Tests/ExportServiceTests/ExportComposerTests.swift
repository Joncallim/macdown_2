import ExportService
import Foundation
import MarkdownEngine
import Testing
import Themes

/// Slice 1: ordinary deterministic HTML, URL security, metadata, theme, and
/// template. Exercises the full composer through the public `ExportService`.
struct ExportComposerTests {
    @Test func frontMatterTitleLandsInDocumentMetadata() async throws {
        let markdown = """
        ---
        title: My Title
        ---
        # Hello
        """
        let prepared = try await ExportService.prepare(
            ExportRequest(text: markdown, sourceGeneration: 1, theme: ExportTestSupport.lightTheme()),
            target: .html(url: URL(fileURLWithPath: "/tmp/out.html"), mode: .selfContained)
        )
        #expect(prepared.title == "My Title")

        let html = ExportHTMLWriter.selfContainedHTML(from: prepared)
        #expect(html.contains("<title>My Title</title>"))
        #expect(html.contains("<h1>Hello</h1>"))
    }

    @Test func ordinaryHTMLPreservesAuthoredRawHTML() async throws {
        let markdown = "# Hi\n\n<div class=\"note\">raw</div>\n"
        let prepared = try await ExportService.prepare(
            ExportRequest(text: markdown, sourceGeneration: 2, theme: ExportTestSupport.lightTheme()),
            target: .html(url: URL(fileURLWithPath: "/tmp/out.html"), mode: .standalone(style: .embedded))
        )
        #expect(prepared.preservesRawHTML)
        #expect(prepared.bodyHTML.contains("<div class=\"note\">raw</div>"))
    }

    @Test func selfContainedHTMLRejectsAuthoredRawHTML() async throws {
        let markdown = "# Hi\n\n<div class=\"note\">raw</div>\n"
        let prepared = try await ExportService.prepare(
            ExportRequest(text: markdown, sourceGeneration: 3, theme: ExportTestSupport.lightTheme()),
            target: .html(url: URL(fileURLWithPath: "/tmp/out.html"), mode: .selfContained)
        )
        #expect(!prepared.preservesRawHTML)
        #expect(!prepared.bodyHTML.contains("<div class=\"note\">raw</div>"))
    }

    @Test func selfContainedEmbedsLocalImageAsDataURI() async throws {
        let directory = try ExportTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let bytes = Data([0x89, 0x50, 0x4E, 0x47, 0x01, 0x02, 0x03])
        try ExportTestSupport.writeFixture(named: "images/foo.png", in: directory, bytes: bytes)

        let markdown = "# Img\n\n![alt](images/foo.png)\n"
        let prepared = try await ExportService.prepare(
            ExportRequest(
                text: markdown,
                sourceGeneration: 4,
                theme: ExportTestSupport.lightTheme(),
                documentDirectory: directory
            ),
            target: .html(url: URL(fileURLWithPath: "/tmp/out.html"), mode: .selfContained)
        )

        #expect(prepared.manifest.resources.count == 1)
        let resource = try #require(prepared.manifest.resources.first)
        #expect(resource.identity.mimeType == "image/png")

        let html = ExportHTMLWriter.selfContainedHTML(from: prepared)
        #expect(html.contains("data:image/png;base64,"))
        #expect(!html.contains("images/foo.png"))
    }

    @Test func selfContainedFailsOnMissingLocalImage() async throws {
        let directory = try ExportTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let markdown = "# Img\n\n![alt](missing.png)\n"
        await #expect(throws: ExportError.self) {
            _ = try await ExportService.prepare(
                ExportRequest(
                    text: markdown,
                    sourceGeneration: 5,
                    theme: ExportTestSupport.lightTheme(),
                    documentDirectory: directory
                ),
                target: .html(url: URL(fileURLWithPath: "/tmp/out.html"), mode: .selfContained)
            )
        }
    }

    @Test func ordinaryHTMLWarnsOnMissingLocalImageButContinues() async throws {
        let directory = try ExportTestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let markdown = "# Img\n\n![alt](missing.png)\n"
        let prepared = try await ExportService.prepare(
            ExportRequest(
                text: markdown,
                sourceGeneration: 6,
                theme: ExportTestSupport.lightTheme(),
                documentDirectory: directory
            ),
            target: .html(url: URL(fileURLWithPath: "/tmp/out.html"), mode: .standalone(style: .embedded))
        )
        #expect(prepared.diagnostics.contains { $0.severity == .warning && $0.message.contains("missing.png") })
        #expect(prepared.bodyHTML.contains("missing.png"))
    }

    @Test func dangerousAuthoredLinkIsBlanked() async throws {
        let markdown = "[x](javascript:alert(1))\n"
        let prepared = try await ExportService.prepare(
            ExportRequest(text: markdown, sourceGeneration: 7, theme: ExportTestSupport.lightTheme()),
            target: .html(url: URL(fileURLWithPath: "/tmp/out.html"), mode: .standalone(style: .embedded))
        )
        #expect(!prepared.bodyHTML.contains("javascript:"))
    }

    @Test func themeVariablesAppearInStylesheet() async throws {
        let prepared = try await ExportService.prepare(
            ExportRequest(text: "# Hi", sourceGeneration: 8, theme: ExportTestSupport.lightTheme()),
            target: .html(url: URL(fileURLWithPath: "/tmp/out.html"), mode: .selfContained)
        )
        #expect(prepared.stylesheet.contains("--md-background"))
        #expect(prepared.stylesheet.contains("--md-foreground"))
    }

    @Test func pdfTargetCarriesNoHTMLOptions() async throws {
        // PDF composition uses the ordinary raw-HTML policy and requires
        // resolvable resources, but never embeds into a linked-CSS shape.
        let markdown = "# Hi\n\n<div>x</div>\n"
        let prepared = try await ExportService.prepare(
            ExportRequest(text: markdown, sourceGeneration: 9, theme: ExportTestSupport.lightTheme()),
            target: .pdf(url: URL(fileURLWithPath: "/tmp/out.pdf"))
        )
        #expect(prepared.preservesRawHTML)
    }

    @Test func sourceGenerationIsCarriedAsUInt() async throws {
        let generation: UInt = 123_456
        let prepared = try await ExportService.prepare(
            ExportRequest(text: "# Hi", sourceGeneration: generation, theme: ExportTestSupport.lightTheme()),
            target: .html(url: URL(fileURLWithPath: "/tmp/out.html"), mode: .selfContained)
        )
        #expect(prepared.sourceGeneration == generation)
    }
}
