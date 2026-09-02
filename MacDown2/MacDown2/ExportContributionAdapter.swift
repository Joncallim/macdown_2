import Contributions
import ExportService

/// Turns contribution results into `ExportDerivedContribution`, the type
/// E12's already-built `DerivedContentComposer` consumes
/// (epic-14-implementation.md §6.6, §7.1). A standalone type, not an
/// extension on `ExportCoordinator`, so it stays trivially unit-testable
/// without constructing a real coordinator.
enum ExportContributionAdapter {
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
    /// thrown failure, §6.1) is dropped entirely: `ExportDerivedContribution`
    /// requires a `sourceRange` to anchor to, and E12 built no facility for
    /// an anchorless diagnostic. A designed failure — a contribution that
    /// anchored real content but reported an `.error` diagnostic on it — is
    /// still fully visible, since that result keeps its `content`.
    static func exportContributions(from results: [ContributionResult]) -> [ExportDerivedContribution] {
        results.compactMap { result in
            guard let content = result.content else { return nil }

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

            return ExportDerivedContribution(
                sourceRange: content.sourceRange,
                placement: exportPlacement(for: content.placement),
                html: html,
                sourceGeneration: result.sourceGeneration,
                diagnostics: diagnostics
            )
        }
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
