import Contributions
import ExportService
import Foundation
@testable import MacDown2
import MarkdownEngine
import Testing
import Themes

/// The full pipeline (epic-20-implementation.md §7.1), end to end with the
/// REAL `MermaidWebRenderer` (genuine WebKit/bundled Mermaid rendering, not
/// a fake) — mirrors `MathExportRegistryTests`' identical "not just this
/// adapter in isolation" standard.
@Suite("MermaidExportRegistry")
struct MermaidExportRegistryTests {
    @Test func standardForExportRunsMermaidButNotForPreview() {
        let registry = ContributionRegistry.standardForExport(theme: BundledThemes.light, isPrintTarget: false)
        #expect(registry.contributions.contains { $0.id == "mermaid" })
        #expect(registry.contributions.contains { $0.id == "math" })
        #expect(registry.contributions.contains { $0.id == "toc" })
        // `.standard` (Preview's registry) is untouched by this factory —
        // epic-20-implementation.md §2.2 invariant.
        #expect(!ContributionRegistry.standard.contributions.contains { $0.id == "mermaid" })
    }

    @Test func mermaidRenderContextUsesNeutralLightPolicyForEveryDestination() {
        let darkPreview = ContributionRegistry.mermaidRenderContext(
            theme: BundledThemes.dark, isPrintTarget: false
        )
        let lightPrint = ContributionRegistry.mermaidRenderContext(
            theme: BundledThemes.light, isPrintTarget: true
        )

        #expect(darkPreview == .neutralLight)
        #expect(lightPrint == .neutralLight)
    }

    @Test func printExportRendersSequenceDiagramWithPrintSafeColors() async throws {
        let text = "```mermaid\nsequenceDiagram\n    Alice->>Bob: Hello\n```\n"
        let parsed = try await ParseEngine().parse(text, revision: 0)
        let registry = ContributionRegistry.standardForExport(theme: BundledThemes.dark, isPrintTarget: true)
        let results = try await registry.run(document: parsed, sourceText: text, sourceGeneration: 1)
        let contribution = try #require(results.first)
        let content = try #require(contribution.content)
        let rendered: String = switch content.representation {
        case let .markdown(value), let .html(value):
            value
        }
        #expect(rendered.localizedCaseInsensitiveContains("<svg"))
        #expect(rendered.localizedCaseInsensitiveContains("Alice"))
        #expect(rendered.localizedCaseInsensitiveContains("Bob"))
        #expect(rendered.localizedCaseInsensitiveContains("Hello"))
        let regexOptions: String.CompareOptions = [.regularExpression, .caseInsensitive]
        #expect(rendered.range(of: ##"stroke:#1A1A1A|stroke="#1A1A1A""##, options: regexOptions) != nil)
        #expect(rendered.range(of: ##"fill:#FFFFFF|fill="#FFFFFF""##, options: regexOptions) != nil)
    }

    @Test func aRealMermaidFenceComposesIntoSelfContainedHTMLWithNoExternalReferences() async throws {
        let text = "# Title\n\n[TOC]\n\nA flow:\n\n```mermaid\ngraph TD; A-->B;\n```\n\n## Section\n"
        let parsed = try await ParseEngine().parse(text, revision: 0)
        let registry = ContributionRegistry.standardForExport(theme: BundledThemes.light, isPrintTarget: false)
        let results = try await registry.run(document: parsed, sourceText: text, sourceGeneration: 9)
        let adaptation = ExportContributionAdapter.adapt(results, destination: .htmlExport)

        // TOC + the one diagram actually placed content — proves the
        // registry change and the .html pass-through are wired together for
        // real, not merely independently unit-tested.
        #expect(adaptation.contributions.count == 2)
        #expect(adaptation.standaloneDiagnostics.isEmpty)

        let request = ExportRequest(
            text: text, sourceGeneration: 9, theme: BundledThemes.light, contributions: adaptation.contributions
        )
        let target = ExportTarget.html(
            url: URL(fileURLWithPath: "/tmp/mermaid-export-registry-test.html"),
            mode: .standalone(style: .embedded)
        )
        let prepared = try await ExportService.prepare(request, target: target)

        #expect(prepared.bodyHTML.contains("Section"))
        #expect(prepared.bodyHTML.contains("<svg"))
        #expect(!prepared.bodyHTML.contains("```mermaid"))
        #expect(!prepared.bodyHTML.contains("[TOC]"))
        #expect(!prepared.bodyHTML.contains("<script"))
        // SVG's own namespace declarations (`xmlns="http://www.w3.org/2000/svg"`,
        // `xmlns="http://www.w3.org/1999/xhtml"` on Mermaid's `foreignObject`
        // labels) are inert identifier strings, not network references — the
        // real self-containment check is that nothing points AT an external
        // resource: no `src="http`/`href="http` attribute value, and no
        // script-driven network call.
        #expect(!prepared.bodyHTML.contains("src=\"http"))
        #expect(!prepared.bodyHTML.contains("href=\"http"))
        #expect(!prepared.bodyHTML.contains("fetch("))
    }

    /// A malformed diagram must not corrupt the exported document — the
    /// authored fence text is preserved and an error diagnostic is
    /// recorded, matching every other failed-contribution behavior
    /// (epic-20-implementation.md §9).
    @Test func aMalformedMermaidFenceLeavesAuthoredSourceUntouchedWithADiagnostic() async throws {
        let text = "```mermaid\ngraph TD; A-->\n```\n"
        let parsed = try await ParseEngine().parse(text, revision: 0)
        let registry = ContributionRegistry.standardForExport(theme: BundledThemes.light, isPrintTarget: false)
        let results = try await registry.run(document: parsed, sourceText: text, sourceGeneration: 0)

        #expect(results.count == 1)
        let result = try #require(results.first)
        #expect(result.content == nil)
        #expect(result.diagnostics.first?.severity == .error)
    }
}
