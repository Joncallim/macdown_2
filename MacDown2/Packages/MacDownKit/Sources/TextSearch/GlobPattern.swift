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
        return matches(tokens: tokens[...], text: Array(text.lowercased())[...])
    }

    private enum Token: Equatable {
        case literal(Character)
        case star
        case doubleStar
    }

    private static func tokenize(_ pattern: String) -> [Token] {
        var tokens: [Token] = []
        let characters = Array(pattern)
        var index = 0
        while index < characters.count {
            if characters[index] == "*" {
                if index + 1 < characters.count, characters[index + 1] == "*" {
                    tokens.append(.doubleStar)
                    index += 2
                    // "**/" means "zero or more whole directories" -- the
                    // separator immediately after `**` is part of the
                    // wildcard itself, not a literal `/` the matched text
                    // must also contain (so "**/*.md" matches "README.md"
                    // at the root, not only a nested one).
                    if index < characters.count, characters[index] == "/" {
                        index += 1
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
    private static func matches(tokens: ArraySlice<Token>, text: ArraySlice<Character>) -> Bool {
        guard let first = tokens.first else { return text.isEmpty }
        switch first {
        case let .literal(character):
            guard let firstText = text.first, firstText == character else { return false }
            return matches(tokens: tokens.dropFirst(), text: text.dropFirst())
        case .star:
            var index = text.startIndex
            while true {
                if matches(tokens: tokens.dropFirst(), text: text[index...]) { return true }
                guard index < text.endIndex, text[index] != "/" else { return false }
                index += 1
            }
        case .doubleStar:
            var index = text.startIndex
            while true {
                if matches(tokens: tokens.dropFirst(), text: text[index...]) { return true }
                guard index < text.endIndex else { return false }
                index += 1
            }
        }
    }
}
