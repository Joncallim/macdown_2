import Foundation

// MARK: - Structural pair table

/// The structural pairs from the legacy `kMPMatchingCharactersMap`, ported as
/// data. `(`, `[`, `{`, `<`, quotes, CJK brackets, curly quotes, guillemets,
/// and East-Asian angle brackets.
let structuralPairs: [(opener: Character, closer: Character)] = [
    ("(", ")"),
    ("[", "]"),
    ("{", "}"),
    ("<", ">"),
    ("'", "'"),
    ("\"", "\""),
    ("\u{FF08}", "\u{FF09}"), // full-width parentheses
    ("\u{300C}", "\u{300D}"), // corner brackets
    ("\u{300E}", "\u{300F}"), // white corner brackets
    ("\u{2018}", "\u{2019}"), // left/right single quotation
    ("\u{201C}", "\u{201D}"), // left/right double quotation
    ("\u{2039}", "\u{203A}"), // single guillemets
    ("\u{00AB}", "\u{00BB}"), // double guillemets
    ("\u{3008}", "\u{3009}"), // East-Asian single angle brackets
    ("\u{300A}", "\u{300B}"), // East-Asian double angle brackets
]

func structuralCloser(for opener: Character) -> Character? {
    structuralPairs.first { $0.opener == opener }?.closer
}

func structuralOpener(for closer: Character) -> Character? {
    structuralPairs.first { $0.closer == closer }?.opener
}
