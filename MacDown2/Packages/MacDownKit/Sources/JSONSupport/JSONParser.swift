import Foundation

/// Strict, Foundation-only JSON parser.
///
/// Contracts (EPIC-11 §3.3/§3.5):
/// - Operates on an immutable UTF-16 snapshot of the editor text.
/// - Produces exactly one diagnostic for the first invalid construct and
///   stops; no recovery, no partial trees, no replacement text.
/// - Duplicate object keys are rejected with a stable diagnostic and never
///   silently merged.
/// - Top-level scalars are valid documents (RFC 8259 allows any value).
/// - Empty input is invalid with a diagnostic at line 1, column 1.
/// - Malformed UTF-8 is a FileStore concern (byte-level); by the time JSON
///   parsing runs, the text is already decoded.
/// - Container nesting is bounded by ``maxNestingDepth`` (EPIC-11 §3.4's
///   depth policy). Deeper documents are invalid with a diagnostic instead
///   of overflowing the stack.
///
/// The scanner state machine lives in `JSONScanner` (plus its value and
/// string extensions) so the recursive-descent grammar stays reviewable.
public enum JSONParser {
    /// Maximum container (object/array) nesting depth accepted.
    ///
    /// Well beyond real-world documents (hand-authored JSON rarely exceeds
    /// a few dozen levels) while keeping the recursive descent, the outline
    /// build, and the formatter safely within the stack of secondary
    /// analysis threads even in unoptimized (Debug) builds, where frames are
    /// much larger. Documents deeper than this are rejected with a
    /// diagnostic instead of crashing. Verified empirically: the full
    /// parse+outline+format pipeline at this depth passes on test-runner
    /// threads; deeper inputs are rejected before recursion can overflow.
    public static let maxNestingDepth = 64

    public static func parse(_ text: String) -> JSONParseOutcome {
        let units = Array(text.utf16)
        var scanner = JSONScanner(units: units)
        scanner.skipWhitespace()

        guard !scanner.isAtEnd else {
            return .invalid(JSONDiagnostic(
                message: "Empty input: expected a JSON value.",
                line: 1,
                column: 1,
                range: nil
            ))
        }

        let root = scanner.parseValue()
        switch root {
        case let .node(node):
            scanner.skipWhitespace()
            if !scanner.isAtEnd {
                return .invalid(scanner.diagnostic("Unexpected content after the JSON value.", at: scanner.position))
            }
            return .valid(node)
        case let .diagnostic(diagnostic):
            return .invalid(diagnostic)
        }
    }
}
