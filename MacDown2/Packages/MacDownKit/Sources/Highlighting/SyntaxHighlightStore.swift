import EditorCore
import Themes

/// Caches one `SyntaxHighlighting` per tab identity. Parallels `EditorTextSystemStore`.
@MainActor
public final class SyntaxHighlightStore {
    private var highlighters: [String: SyntaxHighlighting] = [:]
    private let registry: GrammarRegistry

    public init(registry: GrammarRegistry = GrammarRegistry()) {
        self.registry = registry
    }

    /// Returns the existing highlighter or builds one for this text system.
    public func highlighter(
        for identity: String,
        textSystem: EditorTextSystem,
        languageID: String?,
        theme: Theme
    ) -> SyntaxHighlighting {
        if let existing = highlighters[identity] {
            return existing
        }
        let newHighlighter = NeonSyntaxHighlighter(
            textSystem: textSystem,
            languageID: languageID,
            theme: theme,
            registry: registry
        )
        highlighters[identity] = newHighlighter
        return newHighlighter
    }

    /// Removes the cached highlighter for `identity` and tears it down.
    public func evict(_ identity: String) {
        highlighters[identity]?.tearDown()
        highlighters.removeValue(forKey: identity)
    }

    /// Removes every cached highlighter. Call when the owning window closes.
    public func evictAll() {
        for highlighter in highlighters.values {
            highlighter.tearDown()
        }
        highlighters.removeAll()
    }

    /// Re-theme every live highlighter.
    public func applyThemeToAll(_ theme: Theme) {
        for highlighter in highlighters.values {
            highlighter.applyTheme(theme)
        }
    }

    /// The identities currently held in the cache.
    public var liveIdentities: Set<String> {
        Set(highlighters.keys)
    }
}
