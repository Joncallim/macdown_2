import Foundation

/// Whether a contribution's content occupies an inline run of text or a
/// whole block. Mirrors `ExportService.ExportDerivedPlacement` exactly, but
/// is independently defined so `Contributions` has no dependency on
/// `ExportService` (epic-14-implementation.md §5).
public enum ContributionPlacement: Sendable, Equatable {
    case inline
    case block
}
