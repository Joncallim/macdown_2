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
            guard let candidates = candidatesByKey[Key(old[oldID])],
                  let nearest = nearestUnclaimed(to: oldID, in: candidates, claimed: claimed)
            else { continue }
            claimed.insert(nearest)
            result.insert(nearest)
        }
        return result
    }

    /// The ascending `candidates` entry closest to `target` that is not yet claimed; on equal distance the lower
    /// ordinal wins. Binary search, then outward — not a filter over every candidate for every id (2000 collapsed
    /// items in a document of 100k identical headings took ~40 s).
    private static func nearestUnclaimed(to target: Int, in candidates: [Int], claimed: Set<Int>) -> Int? {
        var low = 0
        var high = candidates.count
        while low < high {
            let middle = (low + high) / 2
            if candidates[middle] < target {
                low = middle + 1
            } else {
                high = middle
            }
        }
        var left = low - 1
        var right = low
        while left >= 0, claimed.contains(candidates[left]) {
            left -= 1
        }
        while right < candidates.count, claimed.contains(candidates[right]) {
            right += 1
        }
        switch (left >= 0, right < candidates.count) {
        case (false, false): return nil
        case (true, false): return candidates[left]
        case (false, true): return candidates[right]
        case (true, true):
            return target - candidates[left] <= candidates[right] - target ? candidates[left] : candidates[right]
        }
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
