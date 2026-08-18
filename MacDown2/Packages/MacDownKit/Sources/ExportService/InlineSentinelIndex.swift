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

    var isEmpty: Bool { specsBySentinel.isEmpty }

    init(_ specs: [CMarkGFM.CustomNodeSpec]) {
        // An empty sentinel would match everywhere and never advance.
        let usable = specs.filter { !$0.sentinel.isEmpty }
        specsByLengthDescending = usable.sorted { $0.sentinel.count > $1.sentinel.count }
        specsBySentinel = Dictionary(uniqueKeysWithValues: usable.map { ($0.sentinel, $0) })
        searchPrefix = Self.commonPrefix(of: usable.map(\.sentinel))
    }

    /// The earliest sentinel occurrence at or after `start`, or `nil`.
    func firstMatch(in text: String, from start: String.Index) -> Match? {
        guard start < text.endIndex else { return nil }
        guard !searchPrefix.isEmpty else { return earliestBySentinel(in: text, from: start) }

        var cursor = start
        while cursor < text.endIndex,
              let hit = text.range(of: searchPrefix, range: cursor ..< text.endIndex) {
            if let spec = match(startingAt: text[hit.lowerBound...]) {
                return (hit.lowerBound ..< text.index(hit.lowerBound, offsetBy: spec.sentinel.count), spec)
            }
            // A shared prefix that is not a whole sentinel: keep looking past it.
            cursor = text.index(after: hit.lowerBound)
        }
        return nil
    }

    /// The spec whose sentinel starts `text`, preferring the longest match so
    /// overlapping sentinel names stay unambiguous.
    func match(startingAt text: Substring) -> CMarkGFM.CustomNodeSpec? {
        specsByLengthDescending.first { text.hasPrefix($0.sentinel) }
    }

    /// The fallback for sentinels with no shared prefix: search each one and
    /// take whichever occurs first.
    private func earliestBySentinel(in text: String, from start: String.Index) -> Match? {
        var best: Match?
        for spec in specsByLengthDescending {
            guard let found = text.range(of: spec.sentinel, range: start ..< text.endIndex) else { continue }
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
            if prefix.isEmpty { break }
        }
        return prefix
    }
}
