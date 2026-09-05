import Contributions
import ExportService

/// Turns contribution results into `ExportDerivedContribution`, the type
/// E12's already-built `DerivedContentComposer` consumes
/// (epic-14-implementation.md §6.6, §7.1). A standalone type, not an
/// extension on `ExportCoordinator`, so it stays trivially unit-testable
/// without constructing a real coordinator.
enum ExportContributionAdapter {
    /// The result of adapting one contribution run for Export: anchored
    /// contributions `DerivedContentComposer` can place, plus diagnostics
    /// from results that had nothing to anchor to at all (architecture
    /// takeover, pass 9/10). Kept separate from `ExportDerivedContribution`
    /// rather than widening E12's public type — a diagnostic-only result has
    /// no `sourceRange` to attach one to.
    struct Adaptation {
        let contributions: [ExportDerivedContribution]
        let standaloneDiagnostics: [ExportDiagnostic]
    }

    /// Renders each placeable result's `.markdown` representation via
    /// `ExportService.renderMarkdownFragment`. `.html` is a real, typed
    /// case no adapter in this epic handles yet
    /// (epic-14-implementation.md §18): rather than silently dropping it,
    /// this still constructs a contribution with empty `html` — which
    /// `DerivedContentComposer`'s existing empty-html rejection already
    /// preserves authored source for — plus a diagnostic explaining why,
    /// so the first contribution that actually produces `.html` is
    /// visibly incomplete rather than silently missing from the export.
    /// The switch below has no `default:` case, so a third
    /// `ContributionRepresentation` case fails to compile here until this
    /// adapter is updated to decide what it means.
    ///
    /// A `content == nil` result (nothing to do, or a registry-caught
    /// thrown failure, §6.1) carries no `sourceRange` to anchor to, so its
    /// diagnostics — if any — become `standaloneDiagnostics` instead of
    /// being dropped. A designed failure — a contribution that anchored
    /// real content but reported an `.error` diagnostic on it — stays
    /// attached to that contribution, since that result keeps its content
    /// and `DerivedContentComposer` already fails it closed.
    static func adapt(_ results: [ContributionResult]) -> Adaptation {
        var contributions: [ExportDerivedContribution] = []
        var standaloneDiagnostics: [ExportDiagnostic] = []
        for result in results {
            guard let content = result.content else {
                standaloneDiagnostics.append(contentsOf: result.diagnostics.map(exportDiagnostic))
                continue
            }

            let html: String
            var diagnostics = result.diagnostics.map(exportDiagnostic)
            switch content.representation {
            case let .markdown(markdown):
                html = ExportService.renderMarkdownFragment(markdown)
            case .html:
                html = ""
                diagnostics.append(ExportDiagnostic(
                    severity: .error,
                    message: "\(result.contributionID) produced an HTML representation, "
                        + "which export does not support yet; authored source preserved"
                ))
            }

            contributions.append(ExportDerivedContribution(
                sourceRange: content.sourceRange,
                placement: exportPlacement(for: content.placement),
                html: html,
                sourceGeneration: result.sourceGeneration,
                diagnostics: diagnostics
            ))
        }
        return Adaptation(contributions: contributions, standaloneDiagnostics: standaloneDiagnostics)
    }

    private static func exportPlacement(for placement: ContributionPlacement) -> ExportDerivedPlacement {
        switch placement {
        case .inline: .inline
        case .block: .block
        }
    }

    private static func exportDiagnostic(_ diagnostic: ContributionDiagnostic) -> ExportDiagnostic {
        let severity: ExportDiagnostic.Severity = switch diagnostic.severity {
        case .warning: .warning
        case .error: .error
        }
        return ExportDiagnostic(severity: severity, message: diagnostic.message)
    }
}
