import Contributions
import ExportService
import Foundation
@testable import MacDown2
import MarkdownEngine
import Testing
import Themes

/// The full pipeline (epic-19-implementation.md §7.2), end to end with the
/// REAL `MathImageRenderer` (genuine `ImageRenderer`/`SwiftUIMath`
/// rendering, not a fake) — mirrors
/// `ExportContributionAdapterTests.fullRoundTripFromTOCToComposedHTML`'s
/// existing "not just this adapter in isolation" standard for TOC.
@Suite("MathExportRegistry")
struct MathExportRegistryTests {
    @Test func standardForExportRunsMathButNotForPreview() {
        let registry = ContributionRegistry.standardForExport(theme: BundledThemes.light)
        #expect(registry.contributions.contains { $0.id == "math" })
        #expect(registry.contributions.contains { $0.id == "toc" })
        // `.standard` (Preview's registry) is untouched by this factory —
        // epic-19-implementation.md §4 invariant 5.
        #expect(!ContributionRegistry.standard.contributions.contains { $0.id == "math" })
    }

    @Test func mathAndTOCComposeIntoRealSelfContainedHTMLWithNoExternalReferences() async throws {
        let text = "# Title\n\n[TOC]\n\nThe energy is $E = mc^2$ and:\n\n$$\na^2+b^2=c^2\n$$\n\n## Section\n"
        let parsed = try await ParseEngine().parse(text, revision: 0)
        let results = try await ContributionRegistry.standardForExport(theme: BundledThemes.light).run(
            document: parsed, sourceText: text, sourceGeneration: 9
        )
        let adaptation = ExportContributionAdapter.adapt(results)

        // Both contributions actually placed content — proves the registry
        // change and the .html pass-through are wired together for real,
        // not merely independently unit-tested.
        #expect(adaptation.contributions.count == 3) // TOC + 2 equations
        #expect(adaptation.standaloneDiagnostics.isEmpty)

        let request = ExportRequest(
            text: text, sourceGeneration: 9, theme: BundledThemes.light, contributions: adaptation.contributions
        )
        let target = ExportTarget.html(
            url: URL(fileURLWithPath: "/tmp/math-export-registry-test.html"),
            mode: .standalone(style: .embedded)
        )
        let prepared = try await ExportService.prepare(request, target: target)

        #expect(prepared.bodyHTML.contains("Section"))
        #expect(prepared.bodyHTML.contains("data:image/png;base64,"))
        #expect(prepared.bodyHTML.contains("alt=\"E = mc^2\""))
        #expect(prepared.bodyHTML.contains("alt=\"\na^2+b^2=c^2\n\"") || prepared.bodyHTML.contains("a^2+b^2=c^2"))
        #expect(!prepared.bodyHTML.contains("$E = mc^2$"))
        #expect(!prepared.bodyHTML.contains("[TOC]"))
        #expect(!prepared.bodyHTML.contains("http://"))
        #expect(!prepared.bodyHTML.contains("https://"))
        #expect(!prepared.bodyHTML.contains("<script"))
    }
}
