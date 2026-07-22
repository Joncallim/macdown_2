import Foundation
import SwiftTreeSitter
import SwiftTreeSitterLayer
import TreeSitterHTML
import TreeSitterJSON
import TreeSitterMarkdown
import TreeSitterMarkdownInline
import TreeSitterMarkdownInlineResources
import TreeSitterMarkdownResources

/// Maps a `FileFormat.highlightLanguageID` to a tree-sitter `LanguageConfiguration`.
///
/// Lazily builds + caches; every failure is caught and cached as `nil` so a bad
/// grammar downgrades that one language to plain text rather than crashing or
/// failing the build.
@MainActor
public final class GrammarRegistry {
    private var cache: [String: LanguageConfiguration?] = [:]
    private let logger = Logger()

    public init() {}

    /// `nil` ⇒ no grammar for this id ⇒ caller must degrade to plain text. Never throws.
    public func configuration(for highlightLanguageID: String?) -> LanguageConfiguration? {
        guard let id = highlightLanguageID else { return nil }

        if let cached = cache[id] {
            return cached
        }

        let config: LanguageConfiguration? = {
            do {
                return try buildConfiguration(for: id)
            } catch {
                logger.log("Grammar '\(id)' failed to load: \(error)")
                return nil
            }
        }()

        cache[id] = config
        return config
    }

    /// The language provider Neon/SwiftTreeSitterLayer call to resolve injected
    /// languages (e.g. `markdown_inline`, or a fenced code block's info-string
    /// language). Returns `nil` for unknown injected languages so that region
    /// stays plain.
    public var languageProvider: LanguageLayer.LanguageProvider {
        { [weak self] name in
            guard let self else { return nil }
            return configuration(for: name)
        }
    }

    /// Ids the registry can currently satisfy.
    public var supportedLanguageIDs: Set<String> {
        Self.knownLanguageIDs.union(cache.compactMap { $0.value != nil ? $0.key : nil })
    }

    private static let knownLanguageIDs: Set<String> = [
        "markdown",
        "markdown_inline",
        "json",
        "html",
    ]

    private func buildConfiguration(for id: String) throws -> LanguageConfiguration? {
        switch id {
        case "markdown":
            guard let queriesURL = TreeSitterMarkdownResources.queriesURL else { return nil }
            return try configuration(
                language: Language(tree_sitter_markdown()),
                name: "Markdown",
                queriesURL: queriesURL
            )
        case "markdown_inline":
            guard let queriesURL = TreeSitterMarkdownInlineResources.queriesURL else { return nil }
            return try configuration(
                language: Language(tree_sitter_markdown_inline()),
                name: "MarkdownInline",
                queriesURL: queriesURL
            )
        case "json":
            return try configuration(
                language: Language(tree_sitter_json()),
                name: "JSON",
                bundleName: "TreeSitterJSON_TreeSitterJSON"
            )
        case "html":
            return try configuration(
                language: Language(tree_sitter_html()),
                name: "HTML",
                bundleName: "TreeSitterHTML_TreeSitterHTML"
            )
        default:
            return nil
        }
    }

    private func configuration(language: Language, name: String, queriesURL: URL) throws -> LanguageConfiguration? {
        let queries = try Self.loadQueries(for: language, in: queriesURL)
        return LanguageConfiguration(language, name: name, queries: queries)
    }

    private func configuration(language: Language, name: String, bundleName: String) throws -> LanguageConfiguration? {
        guard let queriesURL = Self.queriesURL(bundleName: bundleName) else {
            return nil
        }
        return try configuration(language: language, name: name, queriesURL: queriesURL)
    }

    /// Manually enumerate query `.scm` files and compile them.
    ///
    /// This avoids a `FileManager.enumerator` quirk where requesting the
    /// `isReadableKey` resource key causes some dependency resource bundles to
    /// enumerate as empty even though their files are readable.
    private static func loadQueries(for language: Language, in queriesURL: URL) throws -> [Query.Definition: Query] {
        // Note: `[.skipsHiddenFiles]` causes `contentsOfDirectory` to return empty
        // for some dependency resource bundles, so we enumerate all entries.
        let files = try FileManager.default.contentsOfDirectory(at: queriesURL,
                                                                includingPropertiesForKeys: nil,
                                                                options: [])
        var queries = [Query.Definition: Query]()
        for fileURL in files where fileURL.pathExtension == "scm" && !fileURL.lastPathComponent.hasPrefix(".") {
            let query = try Query(language: language, url: fileURL)
            let definition: Query.Definition
            switch fileURL.lastPathComponent {
            case Query.Definition.injections.filename:
                definition = .injections
            case Query.Definition.highlights.filename:
                definition = .highlights
            case Query.Definition.locals.filename:
                definition = .locals
            default:
                let filename = fileURL.lastPathComponent.replacingOccurrences(of: ".scm", with: "")
                definition = .custom(filename)
            }
            queries[definition] = query
        }
        return queries
    }

    /// Locates the tree-sitter query directory for a resource bundle.
    ///
    /// In app builds the bundle is nested in `Bundle.main`. In SPM test targets
    /// `Bundle.main` points at the SwiftPM runner, so we fall back to the
    /// directory that contains the test bundle / executable that links the
    /// SwiftTreeSitter parser classes.
    private static func queriesURL(bundleName: String) -> URL? {
        let parserBundleDir = Bundle(for: Parser.self).bundleURL.deletingLastPathComponent()
        let mainDir = Bundle.main.bundleURL.deletingLastPathComponent()
        let bundleCandidates = [
            Bundle.main.url(forResource: bundleName, withExtension: "bundle"),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/\(bundleName).bundle"),
            parserBundleDir.appendingPathComponent("\(bundleName).bundle"),
            mainDir.appendingPathComponent("\(bundleName).bundle"),
            mainDir.deletingLastPathComponent().appendingPathComponent("\(bundleName).bundle"),
        ]

        for bundleURL in bundleCandidates {
            guard let bundleURL else { continue }

            // Xcode app bundles place resources under Contents/Resources;
            // SPM debug builds place them directly under the bundle root.
            let queriesCandidates = [
                bundleURL.appendingPathComponent("queries", isDirectory: true),
                bundleURL.appendingPathComponent("Contents/Resources/queries", isDirectory: true),
            ]
            for queriesURL in queriesCandidates where FileManager.default.fileExists(atPath: queriesURL.path) {
                return queriesURL
            }
        }

        return nil
    }
}

// MARK: - Minimal logging

private struct Logger {
    func log(_ message: @autoclosure () -> String) {
        #if DEBUG
            print(message())
        #endif
    }
}
