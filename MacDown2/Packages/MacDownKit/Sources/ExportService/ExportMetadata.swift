import Foundation
import MarkdownEngine

/// The document metadata one export carries.
struct ExportMetadata: Equatable {
    /// The `<title>` element's text. Empty means no `<title>` is emitted.
    let browserTitle: String
    /// The heading rendered at the top of the document, when front matter
    /// supplied one. A filename fallback never becomes a visible heading.
    let visibleTitle: String?
    let diagnostics: [ExportDiagnostic]
}

/// The fixed metadata policy (issue #49). Callers cannot vary it.
///
/// - a non-empty scalar front-matter `title` becomes both the browser title and
///   one visible `<h1>`;
/// - no front-matter title falls back to the saved filename stem for the browser
///   title only — a filename is not a heading the author wrote;
/// - an untitled document with no front-matter title has no browser title;
/// - a non-scalar `title` (a list or a mapping) is reported and then treated as
///   absent, rather than being silently coerced into prose.
enum ExportMetadataResolver {
    static func resolve(frontMatter: [String: FrontMatterValue]?, fileNameStem: String?) -> ExportMetadata {
        guard let declared = frontMatter?["title"] else {
            return ExportMetadata(browserTitle: fileNameStem ?? "", visibleTitle: nil, diagnostics: [])
        }

        guard let scalar = scalarText(of: declared) else {
            let warning = ExportDiagnostic(
                severity: .warning,
                message: "The front-matter \"title\" is not a single value, so it was not used as the "
                    + "document title."
            )
            return ExportMetadata(browserTitle: fileNameStem ?? "", visibleTitle: nil, diagnostics: [warning])
        }

        let trimmed = scalar.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ExportMetadata(browserTitle: fileNameStem ?? "", visibleTitle: nil, diagnostics: [])
        }
        return ExportMetadata(browserTitle: trimmed, visibleTitle: trimmed, diagnostics: [])
    }

    /// The text of a scalar YAML value, or `nil` when the value is a collection.
    private static func scalarText(of value: FrontMatterValue) -> String? {
        switch value {
        case let .string(text): text
        case let .int(number): String(number)
        case let .number(number): String(number)
        case let .bool(flag): String(flag)
        case .array, .dictionary, .null: nil
        }
    }
}
