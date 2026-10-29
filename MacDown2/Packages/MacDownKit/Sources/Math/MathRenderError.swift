import Foundation

/// Rendering failures are isolated to their equation. `SwiftUIMath` does not
/// expose public parse-error detail, so its empty output maps to
/// `couldNotTypeset`; invalid renderer dimensions are a separate output
/// failure, not a claim that the author's equation has invalid syntax.
public enum MathRenderError: Error, Sendable, Equatable {
    case couldNotTypeset
    case invalidImageDimensions
}
