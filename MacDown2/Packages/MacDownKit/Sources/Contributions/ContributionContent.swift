import Foundation

/// The placeable part of a contribution's result: where it goes and what it
/// contains. Split out of `ContributionResult` so a contribution that found
/// nothing to do, or that failed before it could anchor a range, can report
/// `content: nil` without needing placeholder values for fields that do not
/// apply (epic-14-implementation.md §6.1).
public struct ContributionContent: Sendable, Equatable {
    /// UTF-16 offsets into the ORIGINAL source this content replaces. Must
    /// be non-empty — `DerivedContentComposer` (ExportService) already
    /// rejects a zero-width range, so every contribution anchors to real,
    /// non-empty authored text (e.g. TOC's `[TOC]` marker line) rather than
    /// a zero-width insertion point.
    public let sourceRange: Range<Int>

    public let placement: ContributionPlacement

    public let representation: ContributionRepresentation

    public init(
        sourceRange: Range<Int>,
        placement: ContributionPlacement,
        representation: ContributionRepresentation
    ) {
        self.sourceRange = sourceRange
        self.placement = placement
        self.representation = representation
    }
}
