import Contributions
import ExportService
@testable import MacDown2
import MarkdownEngine
import Testing
import Themes

@Suite("ExportContributionAdapter")
struct ExportContributionAdapterTests {
    @Test func rendersAMarkdownRepresentationToRealHTML() {
        let content = ContributionContent(sourceRange: 0 ..< 5, placement: .block, representation: .markdown("- One"))
        let result = ContributionResult(contributionID: "toc", content: content, sourceGeneration: 4)

        let exported = ExportContributionAdapter.exportContributions(from: [result])

        #expect(exported.count == 1)
        #expect(exported.first?.html.contains("<li>One</li>") == true)
        #expect(exported.first?.sourceRange == 0 ..< 5)
        #expect(exported.first?.placement == .block)
        #expect(exported.first?.sourceGeneration == 4)
        #expect(exported.first?.diagnostics.isEmpty == true)
    }

    @Test func mapsInlinePlacement() {
        let content = ContributionContent(sourceRange: 2 ..< 4, placement: .inline, representation: .markdown("x"))
        let result = ContributionResult(contributionID: "t", content: content, sourceGeneration: 0)

        let exported = ExportContributionAdapter.exportContributions(from: [result])

        #expect(exported.first?.placement == .inline)
    }

    /// `.html` is a real, typed case no adapter in this epic handles yet
    /// (epic-14-implementation.md §18): it must not silently vanish, and it
    /// must not place unrendered content either — DerivedContentComposer's
    /// existing empty-html rejection preserves the authored source.
    @Test func anHTMLRepresentationProducesEmptyHTMLWithADiagnostic() {
        let content = ContributionContent(sourceRange: 0 ..< 3, placement: .block, representation: .html("<p>x</p>"))
        let result = ContributionResult(contributionID: "future", content: content, sourceGeneration: 1)

        let exported = ExportContributionAdapter.exportContributions(from: [result])

        #expect(exported.count == 1)
        #expect(exported.first?.html.isEmpty == true)
        #expect(exported.first?.diagnostics.contains { $0.severity == .error } == true)
    }

    @Test func aContentlessResultIsDropped() {
        let result = ContributionResult(
            contributionID: "broken", content: nil, sourceGeneration: 0,
            diagnostics: [ContributionDiagnostic(severity: .error, message: "boom")]
        )

        #expect(ExportContributionAdapter.exportContributions(from: [result]).isEmpty)
    }

    @Test func forwardsAPlacedResultsOwnDiagnosticsAlongsideItsContent() {
        let content = ContributionContent(sourceRange: 0 ..< 3, placement: .block, representation: .markdown("x"))
        let result = ContributionResult(
            contributionID: "t", content: content, sourceGeneration: 0,
            diagnostics: [ContributionDiagnostic(severity: .warning, message: "heads up")]
        )

        let exported = ExportContributionAdapter.exportContributions(from: [result])

        #expect(exported.first?.diagnostics.first?.message == "heads up")
        #expect(exported.first?.diagnostics.first?.severity == .warning)
    }

    /// The full pipeline (epic-14-implementation.md §7.1): a real
    /// `TOCContribution` run against a real parse, adapted, and spliced by
    /// E12's already-shipped `DerivedContentComposer` into real composed
    /// HTML — not just this adapter in isolation.
    @Test func fullRoundTripFromTOCToComposedHTML() async throws {
        let text = "# Title\n\n[TOC]\n\n## Section One\n\n## Section Two\n"
        let parsed = try await ParseEngine().parse(text, revision: 0)
        let results = try await ContributionRegistry.standard.run(
            document: parsed, sourceText: text, sourceGeneration: 5
        )
        let contributions = ExportContributionAdapter.exportContributions(from: results)

        let request = ExportRequest(
            text: text, sourceGeneration: 5, theme: BundledThemes.light, contributions: contributions
        )
        let target = ExportTarget.html(
            url: URL(fileURLWithPath: "/tmp/export-contribution-adapter-test.html"),
            mode: .standalone(style: .embedded)
        )
        let prepared = try await ExportService.prepare(request, target: target)

        #expect(prepared.bodyHTML.contains("Section One"))
        #expect(prepared.bodyHTML.contains("Section Two"))
        #expect(!prepared.bodyHTML.contains("[TOC]"))
    }
}
