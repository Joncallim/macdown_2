import Foundation

/// The inline sentinels to substitute, indexed for a single-scan search.
///
/// Every sentinel produced by one export shares a family prefix, so the scan
/// looks for that prefix once per text run instead of once per sentinel — the
/// difference between linear and quadratic work on a document with many
/// contributions. Candidates are matched longest-first, so a sentinel can never
/// be mistaken for the prefix of a longer one.
struct InlineSentinelIndex {
    /// One sentinel occurrence: where it sits and what replaces it.
    typealias Match = (range: Range<String.Index>, spec: CMarkGFM.CustomNodeSpec)

    let specsByLengthDescending: [CMarkGFM.CustomNodeSpec]
    let specsBySentinel: [String: CMarkGFM.CustomNodeSpec]
    /// The prefix shared by every sentinel, or empty when they share none.
    let searchPrefix: String
    /// The longest sentinel in unicode scalars: how far into the text its closing `Z` can sit.
    private let longestSentinelLength: Int

    var isEmpty: Bool {
        specsBySentinel.isEmpty
    }

    init(_ specs: [CMarkGFM.CustomNodeSpec]) {
        // An empty sentinel would match everywhere and never advance.
        let usable = specs.filter { !$0.sentinel.isEmpty }
        specsByLengthDescending = usable.sorted { $0.sentinel.count > $1.sentinel.count }
        specsBySentinel = Dictionary(uniqueKeysWithValues: usable.map { ($0.sentinel, $0) })
        searchPrefix = Self.commonPrefix(of: usable.map(\.sentinel))
        longestSentinelLength = usable.map(\.sentinel.unicodeScalars.count).max() ?? 0
    }

    /// The earliest sentinel occurrence at or after `start`, or `nil`.
    ///
    /// Matched over unicode scalars, not `Character`s: a sentinel's final `Z` followed by a grapheme-extending scalar
    /// (a ZWNJ after Latin text in Persian, ZWJ, VS16, a combining mark) is part of ONE `Character`, which made the
    /// sentinel invisible to Character-level search and prefix tests, leaving it to leak or be exported as source.
    func firstMatch(in text: String, from start: String.Index) -> Match? {
        guard start < text.endIndex else { return nil }
        guard !searchPrefix.isEmpty else { return earliestBySentinel(in: text, from: start) }

        var cursor = start
        while cursor < text.endIndex,
              let hit = text.range(of: searchPrefix, options: .literal, range: cursor ..< text.endIndex) {
            if let spec = match(startingAt: text.unicodeScalars[hit.lowerBound...]) {
                let end = text.unicodeScalars.index(hit.lowerBound, offsetBy: spec.sentinel.unicodeScalars.count)
                return (hit.lowerBound ..< end, spec)
            }
            // A shared prefix that is not a whole sentinel: keep looking past it.
            cursor = text.unicodeScalars.index(after: hit.lowerBound)
        }
        return nil
    }

    /// The spec whose sentinel starts `text`, preferring the longest match so
    /// overlapping sentinel names stay unambiguous.
    func match(startingAt text: Substring.UnicodeScalarView) -> CMarkGFM.CustomNodeSpec? {
        // Sentinels end in `Z` and contain no other `Z` (`DerivedContentComposer.makeSentinel`), so the candidate is
        // everything through the first `Z`: one dictionary lookup instead of a prefix test against every spec
        // (4000 inline contributions took 3.5 s). Any other sentinel shape falls back to the scan.
        if let end = text.prefix(longestSentinelLength).firstIndex(of: "Z"),
           let spec = specsBySentinel[String(text[...end])] {
            return spec
        }
        return specsByLengthDescending.first { text.starts(with: $0.sentinel.unicodeScalars) }
    }

    /// The fallback for sentinels with no shared prefix: search each one and
    /// take whichever occurs first.
    private func earliestBySentinel(in text: String, from start: String.Index) -> Match? {
        var best: Match?
        for spec in specsByLengthDescending {
            guard let found = text.range(of: spec.sentinel, options: .literal, range: start ..< text.endIndex)
            else { continue }
            if best.map({ found.lowerBound < $0.range.lowerBound }) ?? true {
                best = (found, spec)
            }
        }
        return best
    }

    private static func commonPrefix(of sentinels: [String]) -> String {
        guard var prefix = sentinels.first else { return "" }
        for sentinel in sentinels.dropFirst() {
            prefix = prefix.commonPrefix(with: sentinel)
            if prefix.isEmpty {
                break
            }
        }
        return prefix
    }
}
