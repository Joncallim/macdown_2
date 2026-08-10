import Foundation

@MainActor
extension ScrollSyncController {
    var totalHeight: Double {
        cachedTotalHeight
    }

    func offsetUpTo(blockIndex: Int) -> Double {
        offsetsByBlockIndex[blockIndex, default: cachedTotalHeight]
    }

    func height(for blockIndex: Int) -> Double {
        blockHeights[blockIndex, default: 0]
    }

    func entry(forBlockIndex blockIndex: Int) -> ScrollSyncMap.Entry? {
        entriesByBlockIndex[blockIndex]
    }

    /// Uses the source-order index when the map has the normal, disjoint
    /// preview ranges. Preserve the public map's general fallback for unusual
    /// caller-supplied maps with overlapping or unordered ranges.
    func blockIndex(forLine line: Int) -> Int? {
        guard !map.entries.isEmpty else { return nil }
        guard hasOrderedNonOverlappingLineRanges else {
            return map.blockIndex(forLine: line)
        }

        var lower = 0
        var upper = orderedLineStarts.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if orderedLineStarts[middle] <= line {
                lower = middle + 1
            } else {
                upper = middle
            }
        }

        let before = max(lower - 1, 0)
        let candidate = map.entries[before]
        if candidate.lineRange.contains(line) {
            return candidate.blockIndex
        }
        guard lower < map.entries.count else { return candidate.blockIndex }

        let after = map.entries[lower]
        let beforeDistance = abs(candidate.lineRange.lowerBound - line)
        let afterDistance = abs(after.lineRange.lowerBound - line)
        // `min`'s stable tie behavior in ScrollSyncMap favors the earlier
        // entry, which is the candidate before the gap.
        return beforeDistance <= afterDistance ? candidate.blockIndex : after.blockIndex
    }

    func line(forBlockIndex blockIndex: Int) -> Int? {
        entriesByBlockIndex[blockIndex]?.lineRange.lowerBound
    }

    func rebuildHeightIndex() {
        prefixEndHeights.removeAll(keepingCapacity: true)
        prefixEndHeights.reserveCapacity(map.entries.count)
        offsetsByBlockIndex.removeAll(keepingCapacity: true)
        entriesByBlockIndex.removeAll(keepingCapacity: true)
        entriesByBlockIndex.reserveCapacity(map.entries.count)
        orderedLineStarts.removeAll(keepingCapacity: true)
        orderedLineStarts.reserveCapacity(map.entries.count)

        var offset: Double = 0
        var allMeasured = true
        var orderedNonOverlapping = true
        var previousRange: ClosedRange<Int>?
        for entry in map.entries {
            offsetsByBlockIndex[entry.blockIndex] = offset
            entriesByBlockIndex[entry.blockIndex] = entry
            orderedLineStarts.append(entry.lineRange.lowerBound)
            if let previousRange, previousRange.upperBound >= entry.lineRange.lowerBound {
                orderedNonOverlapping = false
            }
            previousRange = entry.lineRange
            let entryHeight = height(for: entry.blockIndex)
            if entryHeight == 0 {
                allMeasured = false
            }
            offset += entryHeight
            prefixEndHeights.append(offset)
        }
        cachedTotalHeight = offset
        allBlockHeightsMeasured = allMeasured
        hasOrderedNonOverlappingLineRanges = orderedNonOverlapping
    }

    func firstPrefixEnd(after value: Double) -> Int? {
        var lower = 0
        var upper = prefixEndHeights.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if prefixEndHeights[middle] > value {
                upper = middle
            } else {
                lower = middle + 1
            }
        }
        return lower < prefixEndHeights.count ? lower : prefixEndHeights.indices.last
    }

    func firstPrefixEnd(atOrAfter value: Double) -> Int? {
        var lower = 0
        var upper = prefixEndHeights.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if prefixEndHeights[middle] >= value {
                upper = middle
            } else {
                lower = middle + 1
            }
        }
        return lower < prefixEndHeights.count ? lower : prefixEndHeights.indices.last
    }

    func line(in entry: ScrollSyncMap.Entry, at target: Double) -> Int {
        let blockStart = offsetsByBlockIndex[entry.blockIndex, default: 0]
        let blockHeight = height(for: entry.blockIndex)
        let local = blockHeight > 0 ? (target - blockStart) / blockHeight : 0
        let lineCount = entry.lineRange.count
        let offset = Int((Double(lineCount) * local).rounded(.down))
        return min(entry.lineRange.lowerBound + offset, entry.lineRange.upperBound)
    }
}
