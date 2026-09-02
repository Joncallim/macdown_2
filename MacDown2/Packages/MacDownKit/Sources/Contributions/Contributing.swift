import Foundation
import MarkdownEngine

/// A first-party contribution: given a parsed document, optionally replace
/// an exact range of its source with generated content. Implementations are
/// trusted, in-process Swift — this protocol has no bearing on the
/// text-filter trust boundary (`TextFilters`), which launches unsandboxed
/// external processes instead.
///
/// A contribution is not a SwiftUI preview view and does not know whether
/// it is feeding Preview or Export; `ContributionResult`'s representation
/// is adapted for each destination at the app layer
/// (epic-14-implementation.md §7).
public protocol Contributing: Sendable {
    /// Stable, never user-facing (diagnostics/tests only), e.g. "toc".
    var id: String { get }

    /// Produces zero or more results for one document snapshot. Called
    /// fresh per caller — Preview and Export each call this independently,
    /// from their own parse of what should be the same text — so a
    /// contribution must not cache anything across calls.
    ///
    /// Cooperatively cancellable: long-running work must poll
    /// `Task.isCancelled` or use `Task.checkCancellation()`, mirroring
    /// `MarkdownParseSession`. May throw for a genuinely unexpected
    /// failure; `ContributionRegistry.run(document:sourceText:sourceGeneration:)`
    /// isolates a thrown error to this one contribution's result rather
    /// than letting it prevent every other registered contribution from
    /// running.
    func run(
        document: MarkdownDocument,
        sourceText: String,
        sourceGeneration: UInt
    ) async throws -> [ContributionResult]
}
