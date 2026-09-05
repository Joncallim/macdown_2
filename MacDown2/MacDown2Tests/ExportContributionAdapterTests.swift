import Contributions
import ExportService
import Foundation
@testable import MacDown2
import MarkdownEngine
import Testing
import Themes

@Suite("ExportContributionAdapter")
struct ExportContributionAdapterTests {
    @Test func rendersAMarkdownRepresentationToRealHTML() {
        let content = ContributionContent(sourceRange: 0 ..< 5, placement: .block, representation: .markdown("- One"))
        let result = ContributionResult(contributionID: "toc", content: content, sourceGeneration: 4)

        let adaptation = ExportContributionAdapter.adapt([result])

        #expect(adaptation.contributions.count == 1)
        #expect(adaptation.contributions.first?.html.contains("<li>One</li>") == true)
        #expect(adaptation.contributions.first?.sourceRange == 0 ..< 5)
        #expect(adaptation.contributions.first?.placement == .block)
        #expect(adaptation.contributions.first?.sourceGeneration == 4)
        #expect(adaptation.contributions.first?.diagnostics.isEmpty == true)
        #expect(adaptation.standaloneDiagnostics.isEmpty)
    }

    @Test func mapsInlinePlacement() {
        let content = ContributionContent(sourceRange: 2 ..< 4, placement: .inline, representation: .markdown("x"))
        let result = ContributionResult(contributionID: "t", content: content, sourceGeneration: 0)

        let adaptation = ExportContributionAdapter.adapt([result])

        #expect(adaptation.contributions.first?.placement == .inline)
    }

    /// `.html` is a real, typed case no adapter in this epic handles yet
    /// (epic-14-implementation.md §18): it must not silently vanish, and it
    /// must not place unrendered content either — DerivedContentComposer's
    /// existing empty-html rejection preserves the authored source.
    @Test func anHTMLRepresentationProducesEmptyHTMLWithADiagnostic() {
        let content = ContributionContent(sourceRange: 0 ..< 3, placement: .block, representation: .html("<p>x</p>"))
        let result = ContributionResult(contributionID: "future", content: content, sourceGeneration: 1)

        let adaptation = ExportContributionAdapter.adapt([result])

        #expect(adaptation.contributions.count == 1)
        #expect(adaptation.contributions.first?.html.isEmpty == true)
        #expect(adaptation.contributions.first?.diagnostics.contains { $0.severity == .error } == true)
    }

    /// Architecture takeover, pass 9/10: a `content == nil` result has no
    /// `sourceRange` to anchor a contribution to, so its diagnostics surface
    /// as standalone rather than disappearing.
    @Test func aContentlessResultsDiagnosticsBecomeStandalone() {
        let result = ContributionResult(
            contributionID: "broken", content: nil, sourceGeneration: 0,
            diagnostics: [ContributionDiagnostic(severity: .error, message: "boom")]
        )

        let adaptation = ExportContributionAdapter.adapt([result])

        #expect(adaptation.contributions.isEmpty)
        #expect(adaptation.standaloneDiagnostics == [ExportDiagnostic(severity: .error, message: "boom")])
    }

    @Test func aContentlessResultWithNoDiagnosticsProducesNothing() {
        let result = ContributionResult(contributionID: "quiet", content: nil, sourceGeneration: 0)

        let adaptation = ExportContributionAdapter.adapt([result])

        #expect(adaptation.contributions.isEmpty)
        #expect(adaptation.standaloneDiagnostics.isEmpty)
    }

    /// A content-bearing diagnostic stays on its contribution — it must not
    /// also appear a second time in `standaloneDiagnostics`.
    @Test func forwardsAPlacedResultsOwnDiagnosticsOnlyOnItsContribution() {
        let content = ContributionContent(sourceRange: 0 ..< 3, placement: .block, representation: .markdown("x"))
        let result = ContributionResult(
            contributionID: "t", content: content, sourceGeneration: 0,
            diagnostics: [ContributionDiagnostic(severity: .warning, message: "heads up")]
        )

        let adaptation = ExportContributionAdapter.adapt([result])

        #expect(adaptation.contributions.first?.diagnostics.first?.message == "heads up")
        #expect(adaptation.contributions.first?.diagnostics.first?.severity == .warning)
        #expect(adaptation.standaloneDiagnostics.isEmpty)
    }

    @Test func preservesResultAndDiagnosticOrderAcrossMixedResults() {
        let diagnosticOnly = ContributionResult(
            contributionID: "a", content: nil, sourceGeneration: 0,
            diagnostics: [ContributionDiagnostic(severity: .warning, message: "first")]
        )
        let content = ContributionContent(sourceRange: 0 ..< 1, placement: .inline, representation: .markdown("x"))
        let placed = ContributionResult(contributionID: "b", content: content, sourceGeneration: 0)
        let anotherDiagnosticOnly = ContributionResult(
            contributionID: "c", content: nil, sourceGeneration: 0,
            diagnostics: [ContributionDiagnostic(severity: .warning, message: "second")]
        )

        let adaptation = ExportContributionAdapter.adapt([diagnosticOnly, placed, anotherDiagnosticOnly])

        #expect(adaptation.contributions.count == 1)
        #expect(adaptation.standaloneDiagnostics.map(\.message) == ["first", "second"])
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
        let adaptation = ExportContributionAdapter.adapt(results)

        let request = ExportRequest(
            text: text, sourceGeneration: 5, theme: BundledThemes.light, contributions: adaptation.contributions
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

@Suite("ExportCoordinator diagnostic merge")
struct ExportCoordinatorDiagnosticMergeTests {
    @Test func combinesStandaloneDiagnosticsFirstThenServiceDiagnosticsWithNoDuplicates() {
        let standalone = ExportDiagnostic(severity: .warning, message: "standalone")
        let service = ExportDiagnostic(severity: .error, message: "service")
        let adaptation = ExportContributionAdapter.Adaptation(contributions: [], standaloneDiagnostics: [standalone])

        let merged = ExportCoordinator.combinedDiagnostics(adaptation, [service])

        #expect(merged == [standalone, service])
    }

    @Test func combinesCleanlyWhenEitherSideIsEmpty() {
        let service = ExportDiagnostic(severity: .error, message: "service")
        let emptyAdaptation = ExportContributionAdapter.Adaptation(contributions: [], standaloneDiagnostics: [])

        #expect(ExportCoordinator.combinedDiagnostics(emptyAdaptation, [service]) == [service])
        #expect(ExportCoordinator.combinedDiagnostics(emptyAdaptation, []).isEmpty)
    }
}
