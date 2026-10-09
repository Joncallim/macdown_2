import Foundation

/// A minimal glob matcher backing `FolderSearchFilter`'s include/exclude
/// patterns (issue #112's "include/exclude glob filters"). Supports `*`
/// (any run of characters within one path segment — never crosses `/`) and
/// `**` (any run of characters, including across `/`), the same two
/// wildcards every comparable tool's own glob filter supports (`.gitignore`,
/// ripgrep `--glob`, VS Code's `files.exclude`). Deliberately does not
/// support `?`, character classes, or brace expansion: issue #112 asks for
/// "glob filters," not a full shell-glob grammar, and a small, exhaustively
/// tested matcher for exactly the two wildcards actually needed is safer
/// than a partial implementation of a larger one.
///
/// Matching is case-insensitive throughout (both `pattern` and `text` are
/// lowercased before matching), matching this package's own existing
/// case-insensitive-extension precedent (`FolderSearchFilter`'s original
/// `includedExtensions.lowercased()` handling) rather than introducing a
/// second, silently-different case convention.
enum GlobPattern {
    static func matches(pattern: String, text: String) -> Bool {
        let tokens = tokenize(pattern.lowercased())
        return matches(tokens: tokens[...], text: Array(text.lowercased().unicodeScalars)[...])
    }

    private enum Token: Equatable {
        case literal(Unicode.Scalar)
        case star
        case doubleStar
        /// `**/`: zero or more WHOLE directories (each ending in `/`), never part of a file name.
        case directories
    }

    private static func tokenize(_ pattern: String) -> [Token] {
        var tokens: [Token] = []
        // Unicode scalars, not `Character`s: a `/` followed by a combining mark is one `Character`, which made
        // `drafts/*.md` cross directories and `private/**` miss `private/\u{301}x.md`.
        let characters = Array(pattern.unicodeScalars)
        var index = 0
        while index < characters.count {
            if characters[index] == "*" {
                if index + 1 < characters.count, characters[index + 1] == "*" {
                    index += 2
                    // "**/" means "zero or more whole directories" -- the
                    // separator immediately after `**` is part of the
                    // wildcard itself, not a literal `/` the matched text
                    // must also contain (so "**/*.md" matches "README.md"
                    // at the root, not only a nested one). It is its own
                    // token: as an unrestricted `**` it let `**/foo.md`
                    // match `xfoo.md` and `src/**/config.json` match
                    // `src/notconfig.json`.
                    if index < characters.count, characters[index] == "/" {
                        tokens.append(.directories)
                        index += 1
                    } else {
                        tokens.append(.doubleStar)
                    }
                } else {
                    tokens.append(.star)
                    index += 1
                }
            } else {
                tokens.append(.literal(characters[index]))
                index += 1
            }
        }
        return tokens
    }

    /// Plain recursive backtracking, not regex-compiled and not memoized:
    /// glob patterns here are short (a handful of tokens, user-authored
    /// search-scope filters, not adversarial input) and this runs once per
    /// indexed path per search, not per keystroke, so the straightforward
    /// implementation is the right tradeoff over a compiled matcher's added
    /// complexity and (for `FolderSearchFilter`, a stored, `Equatable`
    /// value type) the awkwardness of caching a compiled representation
    /// across value copies.
    private static func matches(tokens: ArraySlice<Token>, text: ArraySlice<Unicode.Scalar>) -> Bool {
        guard let first = tokens.first else { return text.isEmpty }
        switch first {
        case let .literal(character):
            return matchesLiteral(character, tokens: tokens, text: text)
        case .star:
            return matchesWildcard(tokens: tokens, text: text, crossesSlash: false)
        case .doubleStar:
            return matchesWildcard(tokens: tokens, text: text, crossesSlash: true)
        case .directories:
            return matchesDirectories(tokens: tokens, text: text)
        }
    }

    private static func matchesLiteral(
        _ character: Unicode.Scalar,
        tokens: ArraySlice<Token>,
        text: ArraySlice<Unicode.Scalar>
    ) -> Bool {
        guard let firstText = text.first, firstText == character else { return false }
        return matches(tokens: tokens.dropFirst(), text: text.dropFirst())
    }

    /// Zero directories, or the text up to and including the next `/`, repeatedly.
    private static func matchesDirectories(tokens: ArraySlice<Token>, text: ArraySlice<Unicode.Scalar>) -> Bool {
        var remaining = text
        while true {
            if matches(tokens: tokens.dropFirst(), text: remaining) {
                return true
            }
            guard let slash = remaining.firstIndex(of: "/") else { return false }
            remaining = remaining[(slash + 1)...]
        }
    }

    /// `crossesSlash` is the only difference between `*` and `**`: both try
    /// every possible consumption length (shortest first) and recurse on
    /// the remaining tokens, but `*` refuses to consume past a `/` while
    /// `**` does not.
    private static func matchesWildcard(
        tokens: ArraySlice<Token>,
        text: ArraySlice<Unicode.Scalar>,
        crossesSlash: Bool
    ) -> Bool {
        var index = text.startIndex
        while true {
            if matches(tokens: tokens.dropFirst(), text: text[index...]) {
                return true
            }
            guard index < text.endIndex, crossesSlash || text[index] != "/" else { return false }
            index += 1
        }
    }
}
