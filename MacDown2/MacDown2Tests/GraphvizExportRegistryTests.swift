import Contributions
import ExportService
import Foundation
@testable import MacDown2
import MarkdownEngine
import Testing
import Themes

/// The full pipeline, end to end with the REAL `GraphvizWebRenderer`
/// (genuine WebKit/bundled viz-js rendering, not a fake).
@Suite("GraphvizExportRegistry")
struct GraphvizExportRegistryTests {
    @Test func standardForExportRunsGraphvizButNotForPreview() {
        let registry = ContributionRegistry.standardForExport(theme: BundledThemes.light, isPrintTarget: false)
        #expect(registry.contributions.contains { $0.id == "graphviz" })
        #expect(!ContributionRegistry.standard.contributions.contains { $0.id == "graphviz" })
    }

    @Test func aRealGraphvizFenceComposesIntoSelfContainedHTMLWithNoExternalReferences() async throws {
        let text = "# Title\n\n[TOC]\n\nA flow:\n\n```dot\ndigraph { a -> b; b -> c; }\n```\n\n## Section\n"
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
            url: URL(fileURLWithPath: "/tmp/graphviz-export-registry-test.html"),
            mode: .standalone(style: .embedded)
        )
        let prepared = try await ExportService.prepare(request, target: target)

        #expect(prepared.bodyHTML.contains("Section"))
        #expect(prepared.bodyHTML.contains("<svg"))
        #expect(!prepared.bodyHTML.contains("```dot"))
        #expect(!prepared.bodyHTML.contains("[TOC]"))
        #expect(!prepared.bodyHTML.contains("<script"))
        #expect(!prepared.bodyHTML.contains("src=\"http"))
        #expect(!prepared.bodyHTML.contains("href=\"http"))
    }

    @Test func aMalformedGraphvizFenceLeavesAuthoredSourceUntouchedWithADiagnostic() async throws {
        let text = "```dot\ndigraph { a -> \n```\n"
        let parsed = try await ParseEngine().parse(text, revision: 0)
        let registry = ContributionRegistry.standardForExport(theme: BundledThemes.light, isPrintTarget: false)
        let results = try await registry.run(document: parsed, sourceText: text, sourceGeneration: 0)

        let graphvizResults = results.filter { $0.contributionID == "graphviz" }
        #expect(graphvizResults.count == 1)
        let result = try #require(graphvizResults.first)
        #expect(result.content == nil)
        #expect(result.diagnostics.first?.severity == .error)
    }
}
