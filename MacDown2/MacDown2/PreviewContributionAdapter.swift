import Contributions
import MarkdownEngine
import Preview

/// Turns contribution results into extra `PreviewBlock`s merged into
/// `DocumentEditorSplitView`'s existing `previewBlocks` computation
/// (epic-14-implementation.md §6.6, §7.1). A standalone type with only
/// static functions, not an extension on `DocumentEditorSplitView` — that
/// view's own body is close to SwiftLint's `type_body_length` budget, and
/// every function here works from explicit parameters rather than reaching
/// into the view's private state.
enum PreviewContributionAdapter {
    /// A defensive ceiling (epic-14-implementation.md §11), far beyond any
    /// real `[TOC]` marker count, so a pathological document cannot make
    /// every reparse do unbounded merge work.
    static let maxMergedResults = 64

    /// Runs the standard contribution registry for one document snapshot.
    /// The only error `ContributionRegistry.run` throws is cancellation
    /// (epic-14-implementation.md §6.1) — expected and benign here, since
    /// SwiftUI's `.task(id:)` already supersedes a cancelled run with a
    /// fresh one, so it is swallowed rather than propagated to a caller
    /// that cannot `throws` from a `.task(id:)` closure.
    static func results(document: MarkdownDocument?, text: String?, generation: UInt) async -> [ContributionResult] {
        guard let document, let text else { return [] }
        do {
            return try await ContributionRegistry.standard.run(
                document: document, sourceText: text, sourceGeneration: generation
            )
        } catch {
            return []
        }
    }

    /// Substitutes the base block containing each placeable contribution's
    /// source range with a synthetic `.custom` block carrying its Markdown
    /// representation. Rejects a result whose `sourceGeneration` no longer
    /// matches the current document (defensive — Preview's own generation
    /// is always fresh in practice) and silently caps at
    /// `maxMergedResults`.
    ///
    /// Only a contribution whose marker occupies an entire base block by
    /// itself is substituted precisely; one sharing a multi-line paragraph
    /// with other authored text replaces that whole paragraph. This is a
    /// narrow, accepted limitation of block-granularity substitution —
    /// Preview has no inline-splicing mechanism, unlike Export's
    /// `DerivedContentComposer` — not expected for a marker written on its
    /// own line, which is the only shape `TOCContribution` looks for.
    static func merged(
        base: [PreviewBlock]?,
        contributions: [ContributionResult],
        sourceMap: SourceMap?,
        currentGeneration: UInt
    ) -> [PreviewBlock]? {
        guard let base, let sourceMap, !contributions.isEmpty else { return base }

        let placements = placements(from: contributions, sourceMap: sourceMap, currentGeneration: currentGeneration)
        guard !placements.isEmpty else { return base }

        return base.map { block in
            guard let placement = placements.first(where: { block.lineRange.contains($0.line) }) else {
                return block
            }
            return PreviewBlock(
                kind: .custom(placement.contributionID), source: placement.markdown, lineRange: block.lineRange
            )
        }
    }

    private struct Placement {
        let line: Int
        let contributionID: String
        let markdown: String
    }

    private static func placements(
        from contributions: [ContributionResult],
        sourceMap: SourceMap,
        currentGeneration: UInt
    ) -> [Placement] {
        contributions.prefix(maxMergedResults).compactMap { contribution -> Placement? in
            guard contribution.sourceGeneration == currentGeneration,
                  let content = contribution.content,
                  case let .markdown(markdown) = content.representation
            else { return nil }

            let line = sourceMap.line(atUTF16Offset: content.sourceRange.lowerBound)
            return Placement(line: line, contributionID: contribution.contributionID, markdown: markdown)
        }
    }
}
