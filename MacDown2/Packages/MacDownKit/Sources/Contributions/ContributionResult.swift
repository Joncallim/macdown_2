import Foundation

/// One contribution's answer for one document snapshot.
///
/// `content == nil` means either the contribution found nothing to do (no
/// diagnostics — this is not a failure) or it failed after being asked to
/// run (one or more `.error` diagnostics explain why). A caller never
/// places anything for a `nil`-content result but still surfaces its
/// diagnostics, mirroring `ExportDerivedContribution`'s existing contract
/// that diagnostics are forwarded whether or not content is placed.
public struct ContributionResult: Sendable, Equatable {
    public let contributionID: String
    public let content: ContributionContent?

    /// An opaque, caller-selected snapshot token this result was computed
    /// from — compared only for equality, never interpreted. Preview keys
    /// it to `MarkdownDocument.revision`; Export keys it to the captured
    /// `FileDocument.mutationGeneration` of the snapshot its request was
    /// built from. Used by callers to reject a result that has gone stale
    /// by the time it would be placed (epic-14-implementation.md §7, §9).
    public let sourceGeneration: UInt

    public let diagnostics: [ContributionDiagnostic]

    public init(
        contributionID: String,
        content: ContributionContent?,
        sourceGeneration: UInt,
        diagnostics: [ContributionDiagnostic] = []
    ) {
        self.contributionID = contributionID
        self.content = content
        self.sourceGeneration = sourceGeneration
        self.diagnostics = diagnostics
    }
}
