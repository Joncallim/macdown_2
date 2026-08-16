import Foundation
@testable import Highlighting
import SwiftTreeSitter
import Testing

/// EPIC-11 Gate 5 — grammar registry completeness, dependency resource
/// loading, and per-language capture smoke tests.
///
/// Every advertised highlight language must resolve to a built, query-backed
/// `LanguageConfiguration` (not just a non-nil language), and a representative
/// snippet of each language must produce at least one highlight capture from
/// the shipped query resources. A grammar whose queries fail to load or whose
/// captures never fire is treated as unsupported even if the C parser builds.
@MainActor
struct GrammarRegistryCompletenessTests {
    /// Every id the registry claims (`knownLanguageIDs`) plus the Markdown
    /// pair. This is the shipped-language contract; the consistency test in
    /// `FormatRegistryConsistencyTests` compares this against the format
    /// registry.
    private nonisolated static let advertisedIDs = [
        "markdown",
        "markdown_inline",
        "json",
        "html",
        "yaml",
        "toml",
        "javascript",
        "typescript",
        "python",
        "ruby",
        "css",
        "swift",
        "cpp",
        "bash",
        "sql",
        "xml",
    ]

    private let registry = GrammarRegistry()

    /// A snippet per language that reliably produces at least one capture
    /// from that grammar's `highlights.scm`.
    private nonisolated static let smokeSnippets: [String: String] = [
        "markdown": "# Heading\n\nText with **bold**.\n",
        "markdown_inline": "**bold** and `code`",
        "json": "{\"key\": [1, 2, 3]}",
        "html": "<div class=\"box\">Hello</div>",
        "yaml": "name: MacDown\nversion: 2\n",
        "toml": "name = \"MacDown\"\n[owner]\norg = \"example\"\n",
        "javascript": "const answer = 42;\nfunction greet(name) { return name; }\n",
        "typescript": "interface Box<T> { value: T }\nconst n: number = 1;\n",
        "python": "def greet(name):\n    return f\"hello {name}\"\n",
        "ruby": "class Greeter\n  def greet(name)\n    \"hello #{name}\"\n  end\nend\n",
        "css": ".box { color: red; margin: 0 auto; }\n",
        "swift": "struct Greeter {\n    func greet(_ name: String) -> String { name }\n}\n",
        "cpp": "#include <vector>\nint main() { std::vector<int> v; return 0; }\n",
        "bash": "#!/bin/bash\nfor i in 1 2 3; do echo \"$i\"; done\n",
        "sql": "SELECT id, name FROM users WHERE active = 1;\n",
        "xml": "<catalog><book id=\"1\">Swift</book></catalog>",
    ]

    @Test(arguments: Self.advertisedIDs)
    func advertisedLanguageResolvesWithQueries(_ id: String) {
        let config = registry.configuration(for: id)
        #expect(config != nil, "grammar '\(id)' failed to build or load queries")
        // The query resources must actually be present: a grammar without
        // highlights cannot highlight.
        #expect(config?.queries[.highlights] != nil, "grammar '\(id)' has no highlights query")
    }

    @Test(arguments: Self.advertisedIDs)
    func smokeSnippetProducesCaptures(_ id: String) throws {
        guard let snippet = Self.smokeSnippets[id] else {
            Issue.record("no smoke snippet registered for '\(id)'")
            return
        }
        let captures = try captures(languageID: id, text: snippet)
        #expect(!captures.isEmpty, "grammar '\(id)' produced no captures for its smoke snippet")
    }

    @Test func coldBuildCachesEveryAdvertisedLanguage() {
        let supported = registry.supportedLanguageIDs
        for id in Self.advertisedIDs {
            #expect(supported.contains(id), "registry does not ship grammar '\(id)'")
        }
    }

    /// Regression guard for the XML packaging quirk: tree-sitter-xml copies
    /// `queries/xml` into its resource bundle as a top-level `xml/` directory,
    /// which the registry's query lookup must still find.
    @Test func xmlQueriesResolveThroughNestedBundleDirectory() {
        let config = registry.configuration(for: "xml")
        #expect(config?.queries[.highlights] != nil)
    }

    // MARK: - Helpers

    private func captures(languageID: String, text: String) throws -> [NamedRange] {
        guard let config = registry.configuration(for: languageID) else {
            return []
        }
        let parser = Parser()
        try parser.setLanguage(config.language)
        guard let tree = parser.parse(text),
              let rootNode = tree.rootNode,
              let query = config.queries[.highlights]
        else {
            return []
        }
        let cursor = query.execute(node: rootNode, in: tree)
        cursor.setRange(NSRange(location: 0, length: (text as NSString).length))
        return cursor.highlights()
    }
}
