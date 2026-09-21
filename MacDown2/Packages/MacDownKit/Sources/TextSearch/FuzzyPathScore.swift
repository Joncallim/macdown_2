import Foundation

/// Fuzzy path/name scoring, shared verbatim by Quick Open (Slice 6) and,
/// per issue #117, the command palette's own fuzzy filtering — so the two
/// do not silently diverge in ranking behaviour.
///
/// Ranking preference, highest first (per the epic's required ordering):
/// exact basename match, basename prefix, basename fuzzy subsequence match,
/// path fuzzy subsequence match, else no match. Callers layer a recency/
/// open-file bonus on top of this base score (that bonus depends on
/// workspace/tab state `TextSearch` has no knowledge of, per its "no
/// window/tab knowledge" ownership boundary).
public enum FuzzyPathScore {
    /// Higher is better. `nil` means the query does not fuzzy-match `path`
    /// at all (not every character of `query` appears, in order, within
    /// `path`).
    public static func score(query: String, path: String, basename: String) -> Double? {
        guard !query.isEmpty else { return 0 }
        let foldedQuery = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let foldedBasename = basename.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)

        if foldedBasename == foldedQuery {
            return 1000
        }
        if foldedBasename.hasPrefix(foldedQuery) {
            return 900
        }
        if let basenameScore = subsequenceScore(query: foldedQuery, in: foldedBasename) {
            return 500 + basenameScore
        }
        let foldedPath = path.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        if let pathScore = subsequenceScore(query: foldedQuery, in: foldedPath) {
            return pathScore
        }
        return nil
    }

    /// `nil` if `query`'s characters do not all appear, in order, in
    /// `candidate`. Otherwise a score in `(0, 100]` rewarding tighter
    /// clustering and earlier matches — a classic fuzzy-matcher shape (as
    /// used by Sublime/VS Code/Zed's own Quick Open), not a novel
    /// algorithm: contiguous runs and a match starting at position 0 score
    /// higher than the same characters scattered across the whole string.
    private static func subsequenceScore(query: String, in candidate: String) -> Double? {
        guard !query.isEmpty else { return 0 }
        let candidateChars = Array(candidate)
        let queryChars = Array(query)
        var candidateIndex = 0
        var queryIndex = 0
        var totalGap = 0
        var firstMatchIndex: Int?
        var previousMatchIndex: Int?
        var contiguousRunBonus = 0.0

        while candidateIndex < candidateChars.count, queryIndex < queryChars.count {
            if candidateChars[candidateIndex] == queryChars[queryIndex] {
                if firstMatchIndex == nil {
                    firstMatchIndex = candidateIndex
                }
                if let previous = previousMatchIndex, previous == candidateIndex - 1 {
                    contiguousRunBonus += 1
                } else if let previous = previousMatchIndex {
                    totalGap += candidateIndex - previous - 1
                }
                previousMatchIndex = candidateIndex
                queryIndex += 1
            }
            candidateIndex += 1
        }

        guard queryIndex == queryChars.count, let firstMatch = firstMatchIndex else { return nil }
        let earlyStartBonus = max(0, 20 - firstMatch)
        let gapPenalty = Double(totalGap)
        let score = 50 + contiguousRunBonus * 5 + Double(earlyStartBonus) - gapPenalty
        return max(1, min(99, score))
    }
}
