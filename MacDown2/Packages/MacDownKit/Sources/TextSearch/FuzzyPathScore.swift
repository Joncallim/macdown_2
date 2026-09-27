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
    /// A case/diacritic-folded string plus its `[Unicode.Scalar]`
    /// decomposition, computed once together and reused for both the
    /// exact/prefix checks (need the `String`) and the subsequence scan
    /// (needs the array). Deliberately `Unicode.Scalar`, not `Character`
    /// (an extended grapheme cluster): `Character`'s own grapheme-boundary
    /// detection is real, measurable per-comparison overhead this exact
    /// budget's own performance test found dominates `subsequenceScore`'s
    /// cost at 100k-path scale, even after folding and precomputation
    /// removed every OTHER redundant cost (a `Character`-based version
    /// still missed the 30 ms budget by roughly 5x). Safe here because
    /// `fold`'s own case/diacritic folding already collapses the composed-
    /// vs-decomposed and case distinctions a grapheme-aware comparison
    /// would otherwise exist to handle; a single exotic multi-scalar
    /// grapheme cluster (e.g. an emoji with a modifier) inside a file name
    /// would be compared scalar-by-scalar rather than cluster-by-cluster,
    /// an accepted trade-off for a fuzzy find-as-you-type filter, not a
    /// data-integrity-sensitive path. Internal, not part of the public API
    /// surface — see `score(foldedQuery:foldedPath:foldedBasename:)`'s own
    /// doc comment for who uses it today.
    struct FoldedText: Sendable, Equatable, Hashable {
        let string: String
        let scalars: [Unicode.Scalar]
        /// Bit N set means ASCII code point N (0..<128) appears somewhere in
        /// `scalars`. `queryMask & candidateMask == queryMask` is a
        /// NECESSARY (not sufficient) condition for a subsequence match: if
        /// the candidate is missing even one ASCII character the query
        /// needs, no scan can possibly succeed. Checking this bitmask is
        /// O(1); `subsequenceScore`'s own scan is O(candidate length) — this
        /// lets the common case (a candidate sharing few or no letters with
        /// the query) skip the scan entirely instead of running it only to
        /// discover no match, the single largest remaining contributor to
        /// this exact budget's own performance test missing 30 ms even
        /// after scalar-based comparison and full precomputation (still
        /// ~5-6x over budget with the scan itself as the only remaining
        /// per-candidate cost). A non-ASCII scalar (rare after folding)
        /// contributes no bit, so the mask is deliberately conservative: a
        /// query containing one always leaves this check trivially passing
        /// (both masks agreeing on the bits that matter), never rejecting a
        /// genuine match — only reducing the speed of an already-rare skip.
        let asciiMask: UInt128

        init(_ raw: String) {
            string = fold(raw)
            scalars = Array(string.unicodeScalars)
            var mask: UInt128 = 0
            for scalar in scalars where scalar.isASCII {
                mask |= UInt128(1) << UInt128(scalar.value)
            }
            asciiMask = mask
        }
    }

    /// Higher is better. `nil` means the query does not fuzzy-match `path`
    /// at all (not every character of `query` appears, in order, within
    /// `path`). A single-shot convenience over `score(foldedQuery:foldedPath:foldedBasename:)`
    /// below — folds all three inputs itself, so prefer that overload
    /// instead when scoring the SAME query against many candidates in one
    /// pass (see its own doc comment for why: this one redoes all of that
    /// folding/decomposition work on every call, which is fine once, but is
    /// measurably wasteful work when repeated unchanged across a large
    /// candidate set).
    public static func score(query: String, path: String, basename: String) -> Double? {
        guard !query.isEmpty else { return 0 }
        return score(foldedQuery: FoldedText(query), foldedPath: FoldedText(path), foldedBasename: FoldedText(basename))
    }

    /// Same ranking as `score(query:path:basename:)`, but takes ALREADY
    /// folded/decomposed inputs. For a caller scoring one query against many
    /// candidates in a single pass — `WorkspaceFileIndex.query`, eventually
    /// the command palette's own filtering per issue #117 — the
    /// `query:path:basename:` overload above redoes the SAME folding and
    /// `Array(String)` decomposition of `query` on every single call, which
    /// is redundant, measurably slow work: this exact budget's own
    /// performance test (EPIC-22 §11/§17, Slice 6a) found redoing that work
    /// on every one of 100k calls made a single `query()` call take over
    /// 400 ms against its 30 ms budget, almost entirely in
    /// `folding(options:locale:)`'s own real Unicode normalization plus
    /// `Array(String)`'s own grapheme-cluster segmentation — not the
    /// subsequence scan's own comparison logic. Callers that already hold
    /// pre-folded forms (`IndexedPath.foldedBasename`/`.foldedRelativePath`)
    /// and fold/decompose their own query once per query call should call
    /// this directly.
    static func score(foldedQuery: FoldedText, foldedPath: FoldedText, foldedBasename: FoldedText) -> Double? {
        guard !foldedQuery.string.isEmpty else { return 0 }
        let queryMask = foldedQuery.asciiMask
        // Exact match and prefix match are both STRICTER than a subsequence
        // match (equal implies subsequence; prefix implies subsequence), so
        // if the basename is even missing one ASCII character the query
        // needs, it cannot satisfy any of the three basename-level checks —
        // gating all three behind one bitmask test, not just the scan,
        // skips two string comparisons per rejected candidate on top of the
        // scan itself.
        if queryMask & foldedBasename.asciiMask == queryMask {
            if foldedBasename.string == foldedQuery.string {
                return 1000
            }
            if foldedBasename.string.hasPrefix(foldedQuery.string) {
                return 900
            }
            if let basenameScore = subsequenceScore(query: foldedQuery.scalars, in: foldedBasename.scalars) {
                return 500 + basenameScore
            }
        }
        if queryMask & foldedPath.asciiMask == queryMask,
           let pathScore = subsequenceScore(query: foldedQuery.scalars, in: foldedPath.scalars) {
            return pathScore
        }
        return nil
    }

    /// Case/diacritic folding shared by `FoldedText` and both `score`
    /// overloads, so every consumer folds identically and can never
    /// silently drift.
    private static func fold(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// `nil` if `queryScalars` do not all appear, in order, in
    /// `candidateScalars`. Otherwise a score in `(0, 100]` rewarding tighter
    /// clustering and earlier matches — a classic fuzzy-matcher shape (as
    /// used by Sublime/VS Code/Zed's own Quick Open), not a novel
    /// algorithm: contiguous runs and a match starting at position 0 score
    /// higher than the same characters scattered across the whole string.
    /// Takes already-decomposed `[Unicode.Scalar]` arrays, never a raw
    /// `String` or `[Character]` — see `FoldedText`'s own doc comment for
    /// why scalar comparison, not grapheme-cluster comparison, is both
    /// correct here (post-folding) and required to meet the 100k-path
    /// budget.
    private static func subsequenceScore(query queryScalars: [Unicode.Scalar],
                                         in candidateScalars: [Unicode.Scalar]) -> Double? {
        guard !queryScalars.isEmpty else { return 0 }
        var candidateIndex = 0
        var queryIndex = 0
        var totalGap = 0
        var firstMatchIndex: Int?
        var previousMatchIndex: Int?
        var contiguousRunBonus = 0.0

        while candidateIndex < candidateScalars.count, queryIndex < queryScalars.count {
            if candidateScalars[candidateIndex] == queryScalars[queryIndex] {
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

        guard queryIndex == queryScalars.count, let firstMatch = firstMatchIndex else { return nil }
        let earlyStartBonus = max(0, 20 - firstMatch)
        let gapPenalty = Double(totalGap)
        let score = 50 + contiguousRunBonus * 5 + Double(earlyStartBonus) - gapPenalty
        return max(1, min(99, score))
    }
}
