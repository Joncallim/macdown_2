@testable import EditorCore
import Foundation
import Testing

@Suite("EditorSelectionSet")
struct EditorSelectionSetTests {
    @Test func singleInitIsPrimary() {
        let set = EditorSelectionSet(single: NSRange(location: 3, length: 2))
        #expect(set.primaryRange == NSRange(location: 3, length: 2))
        #expect(!set.isMultiple)
        #expect(set.count == 1)
    }

    @Test func rangesAreSortedAscending() {
        let set = EditorSelectionSet(
            ranges: [
                NSRange(location: 10, length: 1),
                NSRange(location: 0, length: 1),
                NSRange(location: 5, length: 1),
            ],
            primaryIndex: 0
        )
        #expect(set.ranges == [
            NSRange(location: 0, length: 1),
            NSRange(location: 5, length: 1),
            NSRange(location: 10, length: 1),
        ])
    }

    @Test func primaryFollowsItsRangeAfterSort() {
        // primaryIndex 0 is passed BEFORE sorting -- location 10 -- and must
        // still be primary after normalization reorders it to index 2.
        let set = EditorSelectionSet(
            ranges: [
                NSRange(location: 10, length: 1),
                NSRange(location: 0, length: 1),
                NSRange(location: 5, length: 1),
            ],
            primaryIndex: 0
        )
        #expect(set.primaryRange == NSRange(location: 10, length: 1))
    }

    @Test func overlappingRangesMerge() {
        let set = EditorSelectionSet(
            ranges: [NSRange(location: 0, length: 5), NSRange(location: 3, length: 5)],
            primaryIndex: 0
        )
        #expect(set.ranges == [NSRange(location: 0, length: 8)])
    }

    @Test func touchingRangesDoNotMerge() {
        // [0,5) and [5,10) touch but do not overlap -- two carets/selections
        // that share a boundary remain distinct.
        let set = EditorSelectionSet(
            ranges: [NSRange(location: 0, length: 5), NSRange(location: 5, length: 5)],
            primaryIndex: 0
        )
        #expect(set.ranges.count == 2)
    }

    @Test func duplicateZeroLengthRangesAtSamePointMerge() {
        let set = EditorSelectionSet(
            ranges: [NSRange(location: 5, length: 0), NSRange(location: 5, length: 0)],
            primaryIndex: 0
        )
        #expect(set.ranges == [NSRange(location: 5, length: 0)])
    }

    @Test func addRangeMakePrimary() {
        var set = EditorSelectionSet(single: NSRange(location: 0, length: 1))
        set.addRange(NSRange(location: 10, length: 1), makePrimary: true)
        #expect(set.count == 2)
        #expect(set.primaryRange == NSRange(location: 10, length: 1))
    }

    @Test func addRangeKeepsExistingPrimary() {
        var set = EditorSelectionSet(single: NSRange(location: 0, length: 1))
        set.addRange(NSRange(location: 10, length: 1), makePrimary: false)
        #expect(set.primaryRange == NSRange(location: 0, length: 1))
    }

    @Test func removeRangeAtPrimaryIndexPromotesNeighbor() {
        var set = EditorSelectionSet(
            ranges: [
                NSRange(location: 0, length: 1),
                NSRange(location: 5, length: 1),
                NSRange(location: 10, length: 1),
            ],
            primaryIndex: 1
        )
        set.removeRange(at: 1)
        #expect(set.count == 2)
        // primary was removed; clamped to the nearest valid index.
        #expect(set.ranges.contains(set.primaryRange))
    }

    @Test func removeRangeCannotEmptyTheSet() {
        var set = EditorSelectionSet(single: NSRange(location: 0, length: 1))
        set.removeRange(at: 0)
        #expect(set.count == 1) // no-op: never empty
    }

    @Test func collapseToPrimary() {
        var set = EditorSelectionSet(
            ranges: [NSRange(location: 0, length: 1), NSRange(location: 5, length: 1)],
            primaryIndex: 1
        )
        set.collapseToPrimary()
        #expect(set.count == 1)
        #expect(set.primaryRange == NSRange(location: 5, length: 1))
    }

    @Test func clampedToShorterLength() {
        let set = EditorSelectionSet(
            ranges: [NSRange(location: 0, length: 2), NSRange(location: 8, length: 5)],
            primaryIndex: 1
        )
        let clamped = set.clamped(toLength: 6)
        #expect(clamped.ranges.allSatisfy { $0.location + $0.length <= 6 })
    }

    @Test func clampedMergesRangesThatCollapseToSamePoint() {
        let set = EditorSelectionSet(
            ranges: [NSRange(location: 8, length: 2), NSRange(location: 9, length: 3)],
            primaryIndex: 0
        )
        let clamped = set.clamped(toLength: 5) // both ranges clamp into [5,0)
        #expect(clamped.ranges == [NSRange(location: 5, length: 0)])
    }

    // MARK: - AppKit bridge

    @Test func fromEmptyNSValueArrayIsNil() {
        #expect(EditorSelectionSet(selectedRanges: []) == nil)
    }

    @Test func fromNSValueArrayRoundTrips() {
        let original = [
            NSValue(range: NSRange(location: 0, length: 1)),
            NSValue(range: NSRange(location: 5, length: 2)),
        ]
        let set = EditorSelectionSet(selectedRanges: original)
        #expect(set?.ranges == [NSRange(location: 0, length: 1), NSRange(location: 5, length: 2)])
        #expect(set?.asNSValueArray.map(\.rangeValue) == [
            NSRange(location: 0, length: 1),
            NSRange(location: 5, length: 2),
        ])
    }

    @Test func hundredCursorsNormalizeCorrectly() {
        let ranges = (0 ..< 100).map { NSRange(location: $0 * 3, length: 1) }.shuffled()
        let set = EditorSelectionSet(ranges: ranges, primaryIndex: 0)
        #expect(set.count == 100)
        #expect(set.ranges == set.ranges.sorted { $0.location < $1.location })
    }
}
