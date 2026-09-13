import Foundation

/// The one failure signal `MathContribution` can obtain for a span that
/// could not be typeset. `SwiftUIMath` (the underlying rendering library)
/// exposes no public/SPI parse-error detail — only "rendered nothing"
/// (epic-19-implementation.md §2.1) — so there is deliberately no case here
/// carrying a message string; a caller with a more detailed failure reason
/// of its own normalizes to this one case at the `MathImageRendering`
/// boundary (epic-19-implementation.md §6.2).
public enum MathRenderError: Error, Sendable, Equatable {
    case couldNotTypeset
}
