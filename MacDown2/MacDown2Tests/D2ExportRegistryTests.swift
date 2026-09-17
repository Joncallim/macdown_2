import Contributions
import ExportService
import Foundation
@testable import MacDown2
import MarkdownEngine
import Testing
import Themes

/// The full pipeline, end to end with the REAL `D2WebRenderer` (genuine
/// WebKit/bundled D2 rendering, not a fake) — mirrors
/// `MermaidExportRegistryTests`' identical "not just this adapter in
/// isolation" standard.
@Suite("D2ExportRegistry")
struct D2ExportRegistryTests {
    @Test func standardForExportRunsD2ButNotForPreview() {
        let registry = ContributionRegistry.standardForExport(theme: BundledThemes.light, isPrintTarget: false)
        #expect(registry.contributions.contains { $0.id == "d2" })
        #expect(!ContributionRegistry.standard.contributions.contains { $0.id == "d2" })
    }

    @Test func aRealD2FenceComposesIntoSelfContainedHTMLWithNoExternalReferences() async throws {
        let text = "# Title\n\n[TOC]\n\nA flow:\n\n```d2\na -> b -> c\n```\n\n## Section\n"
        let parsed = try await ParseEngine().parse(text, revision: 0)
        let registry = ContributionRegistry.standardForExport(theme: BundledThemes.light, isPrintTarget: false)
        let results = try await registry.run(document: parsed, sourceText: text, sourceGeneration: 9)
        let adaptation = ExportContributionAdapter.adapt(results)

        #expect(adaptation.contributions.count == 2)
        #expect(adaptation.standaloneDiagnostics.isEmpty)

        let request = ExportRequest(
            text: text, sourceGeneration: 9, theme: BundledThemes.light, contributions: adaptation.contributions
        )
        let target = ExportTarget.html(
            url: URL(fileURLWithPath: "/tmp/d2-export-registry-test.html"),
            mode: .standalone(style: .embedded)
        )
        let prepared = try await ExportService.prepare(request, target: target)

        #expect(prepared.bodyHTML.contains("Section"))
        #expect(prepared.bodyHTML.contains("<svg"))
        #expect(!prepared.bodyHTML.contains("```d2"))
        #expect(!prepared.bodyHTML.contains("[TOC]"))
        #expect(!prepared.bodyHTML.contains("<script"))
        #expect(!prepared.bodyHTML.contains("src=\"http"))
        #expect(!prepared.bodyHTML.contains("href=\"http"))
    }

    @Test func aMalformedD2FenceLeavesAuthoredSourceUntouchedWithADiagnostic() async throws {
        let text = "```d2\n{{{ not valid d2 ][\n```\n"
        let parsed = try await ParseEngine().parse(text, revision: 0)
        let registry = ContributionRegistry.standardForExport(theme: BundledThemes.light, isPrintTarget: false)
        let results = try await registry.run(document: parsed, sourceText: text, sourceGeneration: 0)

        let d2Results = results.filter { $0.contributionID == "d2" }
        #expect(d2Results.count == 1)
        let result = try #require(d2Results.first)
        #expect(result.content == nil)
        #expect(result.diagnostics.first?.severity == .error)
    }
}
