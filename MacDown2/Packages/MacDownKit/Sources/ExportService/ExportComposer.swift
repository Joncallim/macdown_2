import Foundation
import MarkdownEngine
import Themes

/// The export composition pipeline (issue #49): live editor snapshot → fresh
/// `ParseExecuting` parse → configured cmark-gfm tree → metadata/theme/resources/
/// derived output → one built-in template → `PreparedExportDocument`.
enum ExportComposer {
    /// What a target does when the source contains authored raw HTML.
    enum RawHTMLPolicy {
        /// Render it as authored (`CMARK_OPT_UNSAFE` + tagfilter), silently.
        case preserve
        /// Render it as authored, but record that it is only best-effort under
        /// the locked-down print stack.
        case preserveWithWarning
        /// Fail the export: a document containing arbitrary resource-bearing
        /// attributes cannot be proven closed, so it must not claim to be.
        case reject
    }

    /// Target-derived policy. Ordinary HTML preserves raw HTML; self-contained
    /// HTML rejects it. PDF and self-contained require resolvable resources.
    struct Policy {
        let rawHTML: RawHTMLPolicy
        let unresolvedResourcesAreFatal: Bool

        /// `CMARK_OPT_UNSAFE` is set for every policy that keeps authored raw
        /// HTML in the output.
        var preservesRawHTML: Bool {
            switch rawHTML {
            case .preserve, .preserveWithWarning: true
            case .reject: false
            }
        }
    }

    static func policy(for target: ExportTarget) -> Policy {
        switch target {
        case let .html(_, mode):
            switch mode {
            case .standalone:
                Policy(rawHTML: .preserve, unresolvedResourcesAreFatal: false)
            case .selfContained:
                Policy(rawHTML: .reject, unresolvedResourcesAreFatal: true)
            }
        case .pdf:
            Policy(rawHTML: .preserveWithWarning, unresolvedResourcesAreFatal: true)
        }
    }

    static func prepare(
        request: ExportRequest,
        target: ExportTarget,
        engine: any ParseExecuting,
        budget: ExportResourceBudget = .standard
    ) async throws -> PreparedExportDocument {
        let policy = policy(for: target)
        try checkSourceBudget(bytes: request.text.utf8.count, budget: budget)

        let sourceUTF16Length = request.text.utf16.count
        let parsed = try await parse(request: request, engine: engine)
        try Task.checkCancellation()

        let derived = DerivedContentComposer.compose(
            bodyText: parsed.bodyText,
            bodyStartOffset: parsed.bodyStartOffset,
            sourceUTF16Length: sourceUTF16Length,
            contributions: request.contributions,
            sourceGeneration: request.sourceGeneration,
            budget: budget
        )

        let resolver = ExportResourceResolver(
            documentDirectory: request.documentDirectory,
            unresolvedIsFatal: policy.unresolvedResourcesAreFatal,
            budget: budget
        )
        let rendered = try renderBody(derived: derived, policy: policy, resolver: resolver)
        try Task.checkCancellation()
        try checkPreparedBudget(bytes: rendered.html.utf8.count, budget: budget)

        let diagnostics = try resolve(
            derived: derived.diagnostics,
            resources: resolver.diagnostics,
            rendered: rendered,
            policy: policy
        )

        return PreparedExportDocument(
            title: parsed.title,
            bodyHTML: rendered.html,
            stylesheet: stylesheet(for: request.theme),
            manifest: resolver.frozenManifest(),
            diagnostics: diagnostics,
            sourceGeneration: request.sourceGeneration,
            preservesRawHTML: policy.preservesRawHTML
        )
    }

    /// The theme block is emitted first and the structural sheet last.
    ///
    /// Media queries do not raise specificity, so the print palette — which must
    /// override the theme, since a dark page prints as unreadable light text on
    /// white paper — only wins if the structural sheet comes second. For screen
    /// rules the order is irrelevant: the structural sheet declares no `--md-*`
    /// value outside `@media print`, so the theme still owns every colour.
    private static func stylesheet(for theme: Theme) -> String {
        ExportThemeStylesheet.variables(for: theme) + "\n" + ExportThemeStylesheet.structural
    }

    /// Applies the target's raw-HTML and resource-closure rules to the composed
    /// diagnostics, throwing when the target's contract cannot be met.
    private static func resolve(
        derived: [ExportDiagnostic],
        resources: [ExportDiagnostic],
        rendered: CMarkGFM.Rendered,
        policy: Policy
    ) throws -> [ExportDiagnostic] {
        if rendered.containsRawHTML, case .reject = policy.rawHTML {
            throw ExportError.rawHTMLNotEmbeddable
        }

        // Only unresolved resources close the export. A failed derived
        // contribution is never fatal on its own: its authored Markdown is still
        // in the body, and its diagnostic is already recorded.
        let unresolved = resources.filter { $0.severity == .error }
        if policy.unresolvedResourcesAreFatal, !unresolved.isEmpty {
            throw ExportError.unresolvedResources(unresolved)
        }

        guard rendered.containsRawHTML, case .preserveWithWarning = policy.rawHTML else {
            return derived + resources
        }
        return derived + resources + [ExportDiagnostic(
            severity: .warning,
            message: "Authored raw HTML is rendered best-effort by the print system; "
                + "it cannot load scripts or remote resources."
        )]
    }

    /// The source gate runs before the parse so a pathological document is
    /// rejected in constant time instead of after a full parse and render.
    private static func checkSourceBudget(bytes: Int, budget: ExportResourceBudget) throws {
        guard bytes > budget.maxSourceUTF8Bytes else { return }
        let limit = ExportResourceBudget.describe(bytes: budget.maxSourceUTF8Bytes)
        throw ExportError.budgetExceeded(
            "the document is \(ExportResourceBudget.describe(bytes: bytes)), over the \(limit) export limit"
        )
    }

    private static func checkPreparedBudget(bytes: Int, budget: ExportResourceBudget) throws {
        guard bytes > budget.maxPreparedHTMLUTF8Bytes else { return }
        let limit = ExportResourceBudget.describe(bytes: budget.maxPreparedHTMLUTF8Bytes)
        throw ExportError.budgetExceeded(
            "the composed document is \(ExportResourceBudget.describe(bytes: bytes)), over the \(limit) export limit"
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
            if error is CancellationError { throw error }
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

    private static func renderBody(
        derived: DerivedContentComposer.Result,
        policy: Policy,
        resolver: ExportResourceResolver
    ) throws -> CMarkGFM.Rendered {
        var options = CMarkGFM.optDefault
        if policy.preservesRawHTML {
            options |= CMarkGFM.optUnsafe
        }
        // Source positions are not emitted into export HTML; smart typography
        // matches the preview's comfortable reading output.
        options |= CMarkGFM.optSmart

        do {
            return try CMarkGFM.render(
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
