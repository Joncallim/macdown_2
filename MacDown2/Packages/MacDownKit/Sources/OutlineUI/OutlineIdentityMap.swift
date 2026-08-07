import MarkdownEngine

/// Carries ordinal-keyed UI state (collapse, selection) across a re-parse
/// (D4). An ordinal is only meaningful relative to the parse that produced
/// it, so a plain `Set<Int>` intersection between old and new trees is not
/// reconciliation: insert one heading above a collapsed node and every old
/// ordinal still exists, so nothing is dropped and the collapse silently
/// slides onto the next section down.
public enum OutlineIdentityMap {
    /// Maps a single old ordinal to its nearest same-`(level, title)` match in
    /// `new`, or `nil` if there is no match (or `id` is `nil`/out of range).
    public static func remap(_ id: Int?, from old: [HeadingItem], to new: [HeadingItem]) -> Int? {
        guard let id else { return nil }
        return remap([id], from: old, to: new).first
    }

    /// Maps each old ordinal in `ids` to the new heading with the same
    /// `(level, title)` whose ordinal is nearest to it. Each new ordinal is
    /// claimed by at most one old id (closest wins, ties broken by ascending
    /// old ordinal); an old id with no remaining candidate is dropped.
    public static func remap(_ ids: Set<Int>, from old: [HeadingItem], to new: [HeadingItem]) -> Set<Int> {
        guard !ids.isEmpty, !old.isEmpty, !new.isEmpty else { return [] }

        var candidatesByKey: [Key: [Int]] = [:]
        for (ordinal, heading) in new.enumerated() {
            candidatesByKey[Key(heading), default: []].append(ordinal)
        }

        var claimed: Set<Int> = []
        var result: Set<Int> = []

        for oldID in ids.sorted() where old.indices.contains(oldID) {
            let key = Key(old[oldID])
            guard let candidates = candidatesByKey[key] else { continue }
            let available = candidates.filter { !claimed.contains($0) }
            guard let nearest = available.min(by: { abs($0 - oldID) < abs($1 - oldID) }) else { continue }
            claimed.insert(nearest)
            result.insert(nearest)
        }
        return result
    }

    private struct Key: Hashable {
        let level: Int
        let title: String

        init(_ heading: HeadingItem) {
            level = heading.level
            title = heading.title
        }
    }
}
