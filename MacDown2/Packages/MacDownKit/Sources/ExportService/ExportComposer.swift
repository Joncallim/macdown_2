import Foundation
import MarkdownEngine

/// The export composition pipeline (issue #49): live editor snapshot → fresh
/// `ParseExecuting` parse → configured cmark-gfm tree → metadata/theme/resources/
/// derived output → one built-in template → `PreparedExportDocument`.
enum ExportComposer {
    /// Target-derived policy. Ordinary HTML preserves raw HTML; self-contained
    /// HTML rejects it. PDF and self-contained require resolvable resources.
    struct Policy {
        let preservesRawHTML: Bool
        let unresolvedResourcesAreFatal: Bool
    }

    static func policy(for target: ExportTarget) -> Policy {
        switch target {
        case let .html(_, mode):
            switch mode {
            case .standalone:
                Policy(preservesRawHTML: true, unresolvedResourcesAreFatal: false)
            case .selfContained:
                Policy(preservesRawHTML: false, unresolvedResourcesAreFatal: true)
            }
        case .pdf:
            Policy(preservesRawHTML: true, unresolvedResourcesAreFatal: true)
        }
    }

    static func prepare(
        request: ExportRequest,
        target: ExportTarget,
        engine: any ParseExecuting
    ) async throws -> PreparedExportDocument {
        let policy = policy(for: target)
        let parsed = try await parse(request: request, engine: engine)

        let derived = DerivedContentComposer.compose(
            bodyText: parsed.bodyText,
            bodyStartOffset: parsed.bodyStartOffset,
            sourceUTF16Length: request.text.utf16.count,
            contributions: request.contributions,
            sourceGeneration: request.sourceGeneration
        )

        let resolver = ExportResourceResolver(
            documentDirectory: request.documentDirectory,
            unresolvedIsFatal: policy.unresolvedResourcesAreFatal
        )
        let bodyHTML = try renderBodyHTML(derived: derived, policy: policy, resolver: resolver)

        let manifest = resolver.frozenManifest()
        let stylesheet = ExportThemeStylesheet.variables(for: request.theme) + "\n" + ExportThemeStylesheet.structural
        let diagnostics = derived.diagnostics + resolver.diagnostics

        if policy.unresolvedResourcesAreFatal,
           diagnostics.contains(where: { $0.severity == .error }) {
            throw ExportError.unresolvedResources(diagnostics)
        }

        return PreparedExportDocument(
            title: parsed.title,
            bodyHTML: bodyHTML,
            stylesheet: stylesheet,
            manifest: manifest,
            diagnostics: diagnostics,
            sourceGeneration: request.sourceGeneration,
            preservesRawHTML: policy.preservesRawHTML
        )
    }

    /// The parsed source: front-matter title, the body text (front matter
    /// stripped), and the body's exact UTF-16 offset within the original text.
    private struct ParsedSource {
        let title: String
        let bodyText: String
        let bodyStartOffset: Int
    }

    private static func parse(
        request: ExportRequest,
        engine: any ParseExecuting
    ) async throws -> ParsedSource {
        // Exact UInt → Int conversion happens only here, at the parser call.
        let revision = Int(exactly: request.sourceGeneration) ?? Int.max
        let document: MarkdownDocument
        do {
            document = try await engine.parse(request.text, options: .default, revision: revision)
        } catch {
            throw ExportError.parseFailed(underlying: error)
        }

        let bodyText = document.body
        // `document.body` is a UTF-16 suffix of the original source (front
        // matter stripped), so the body start offset is exact.
        let bodyStartOffset = request.text.utf16.count - bodyText.utf16.count
        return ParsedSource(
            title: title(from: document),
            bodyText: bodyText,
            bodyStartOffset: bodyStartOffset
        )
    }

    private static func renderBodyHTML(
        derived: DerivedContentComposer.Result,
        policy: Policy,
        resolver: ExportResourceResolver
    ) throws -> String {
        var options = CMarkGFM.optDefault
        if policy.preservesRawHTML {
            options |= CMarkGFM.optUnsafe
        }
        // Source positions are not emitted into export HTML; smart typography
        // matches the preview's comfortable reading output.
        options |= CMarkGFM.optSmart

        do {
            return try CMarkGFM.renderHTML(
                derived.splicedBody,
                options: options,
                customNodes: derived.customNodes,
                urlTransformer: { url, isImage in resolver.disposition(for: url, isImage: isImage) }
            )
        } catch {
            throw ExportError.renderFailed(underlying: error)
        }
    }

    private static func title(from document: MarkdownDocument) -> String {
        guard let values = document.frontMatter?.values,
              case let .string(title) = values["title"] else {
            return ""
        }
        return title
    }
}
