import Foundation

/// Ordered, non-overlapping UTF-16 selection ranges with one designated
/// primary selection — the plural sibling of `EditorTextSystem`'s existing
/// singular `selectedRange`.
///
/// `ranges` is always non-empty, always sorted ascending by `location`, and
/// always pairwise non-overlapping; touching/adjacent ranges (one range's
/// end equal to the next range's start) are permitted and remain distinct —
/// normalization only merges ranges that genuinely overlap. Bridges to/from
/// `NSTextView.selectedRanges`.
public struct EditorSelectionSet: Sendable, Equatable {
    public private(set) var ranges: [NSRange]

    /// Index into `ranges` of the primary selection — the one Preview/
    /// outline tracking follows, and the one a plain Escape collapses to.
    public private(set) var primaryIndex: Int

    public init(single range: NSRange) {
        ranges = [range]
        primaryIndex = 0
    }

    /// Normalizes (sorts, merges overlaps) and validates `primaryIndex`
    /// against the *pre-normalization* identity of the intended primary
    /// range, so a caller's primary selection is still primary after
    /// normalization even if its array index moved.
    public init(ranges: [NSRange], primaryIndex: Int) {
        precondition(!ranges.isEmpty, "EditorSelectionSet requires at least one range")
        let clampedPrimaryIndex = min(max(0, primaryIndex), ranges.count - 1)
        let primaryRangeBeforeNormalization = ranges[clampedPrimaryIndex]
        let normalized = Self.normalize(ranges)
        self.ranges = normalized
        self.primaryIndex = Self.indexClosest(to: primaryRangeBeforeNormalization, in: normalized)
    }

    public var primaryRange: NSRange {
        ranges[primaryIndex]
    }

    public var isMultiple: Bool {
        ranges.count > 1
    }

    public var count: Int {
        ranges.count
    }

    /// Adds one range, re-normalizing. `makePrimary` selects the newly
    /// added range as primary after normalization (used by Option-click add
    /// and add-cursor-above/below); otherwise the existing primary is kept.
    public mutating func addRange(_ range: NSRange, makePrimary: Bool) {
        let previousPrimary = primaryRange
        var updated = ranges
        updated.append(range)
        let normalized = Self.normalize(updated)
        ranges = normalized
        primaryIndex = Self.indexClosest(to: makePrimary ? range : previousPrimary, in: normalized)
    }

    /// Removes the range at `index`. Removing the last remaining range is a
    /// no-op (a selection set is never empty) — callers that want "clear
    /// the selection entirely" should use `collapseToPrimary()` or replace
    /// the whole set, not remove down to zero.
    public mutating func removeRange(at index: Int) {
        guard ranges.count > 1, ranges.indices.contains(index) else { return }
        let removingPrimary = index == primaryIndex
        ranges.remove(at: index)
        if removingPrimary {
            primaryIndex = min(index, ranges.count - 1)
        } else if index < primaryIndex {
            primaryIndex -= 1
        }
    }

    /// Collapses to just the primary selection (Escape).
    public mutating func collapseToPrimary() {
        let primary = primaryRange
        ranges = [primary]
        primaryIndex = 0
    }

    /// Clamps every range against `newLength` after an edit elsewhere
    /// invalidates offsets (mirrors `EditorViewportSnapshot`'s existing
    /// single-range clamp-on-external-reload precedent, generalized to N
    /// ranges). Ranges that collapse to the same clamped position are
    /// merged, since two carets cannot coherently occupy one clamped point.
    public func clamped(toLength newLength: Int) -> EditorSelectionSet {
        let primary = primaryRange
        let clampedRanges = ranges.map { range -> NSRange in
            let location = min(max(0, range.location), newLength)
            let length = min(max(0, range.length), newLength - location)
            return NSRange(location: location, length: length)
        }
        let normalized = Self.normalize(clampedRanges)
        let newPrimaryIndex = Self.indexClosest(
            to: NSRange(location: min(primary.location, newLength), length: 0),
            in: normalized
        )
        return EditorSelectionSet(preNormalized: normalized, primaryIndex: newPrimaryIndex)
    }

    // MARK: - AppKit bridge

    /// `nil` if `selectedRanges` is empty or contains no valid `NSRange`
    /// values — a malformed/empty array from AppKit is never silently
    /// treated as "collapse to zero", since this type cannot represent
    /// zero ranges.
    public init?(selectedRanges: [NSValue]) {
        guard !selectedRanges.isEmpty else { return nil }
        self.init(ranges: selectedRanges.map(\.rangeValue), primaryIndex: 0)
    }

    public var asNSValueArray: [NSValue] {
        ranges.map { NSValue(range: $0) }
    }

    // MARK: - Private

    /// Trusts `ranges` is already sorted/non-overlapping — used internally
    /// once a caller has already normalized, to avoid re-normalizing twice.
    private init(preNormalized ranges: [NSRange], primaryIndex: Int) {
        self.ranges = ranges
        self.primaryIndex = primaryIndex
    }

    private static func normalize(_ ranges: [NSRange]) -> [NSRange] {
        let sorted = ranges.sorted { $0.location != $1.location ? $0.location < $1.location : $0.length < $1.length }
        var merged: [NSRange] = []
        for range in sorted {
            guard var last = merged.last else {
                merged.append(range)
                continue
            }
            // Genuinely overlapping (not merely touching) ranges merge.
            // Genuine overlap merges. Two zero-length ranges at the exact
            // same point are also a merge, not a "touch" — a zero-length
            // range has no extent to touch adjacently with, so two of them
            // at one location are duplicate cursors (an adversarial case
            // the epic explicitly calls out), not two distinct carets that
            // happen to border each other.
            let isDuplicateCaret = range.length == 0 && last.length == 0 && range.location == last.location
            if range.location < last.location + last.length || isDuplicateCaret {
                let end = max(last.location + last.length, range.location + range.length)
                last.length = end - last.location
                merged[merged.count - 1] = last
            } else {
                merged.append(range)
            }
        }
        return merged
    }

    /// The index of the range in `normalized` that best represents
    /// `target` after normalization may have merged/reordered it: prefer a
    /// range that contains `target`'s location, else the closest by start
    /// offset.
    private static func indexClosest(to target: NSRange, in normalized: [NSRange]) -> Int {
        if let containing = normalized.firstIndex(where: {
            $0.location <= target.location && target.location <= $0.location + $0.length
        }) {
            return containing
        }
        guard !normalized.isEmpty else { return 0 }
        var bestIndex = 0
        var bestDistance = Int.max
        for (index, range) in normalized.enumerated() {
            let distance = abs(range.location - target.location)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return bestIndex
    }
}
