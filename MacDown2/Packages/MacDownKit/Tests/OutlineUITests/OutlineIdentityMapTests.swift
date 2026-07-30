@testable import MarkdownEngine
@testable import OutlineUI
import Testing

@Suite("OutlineIdentityMap.remap")
struct OutlineIdentityMapTests {
    @Test func emptyOldOrNewYieldsEmptyResult() {
        let some = [Fixtures.heading(level: 1, title: "A", line: 1)]
        #expect(OutlineIdentityMap.remap([0], from: [], to: some).isEmpty)
        #expect(OutlineIdentityMap.remap([0], from: some, to: []).isEmpty)
    }

    @Test func emptyIDsYieldsEmptyResult() {
        let some = [Fixtures.heading(level: 1, title: "A", line: 1)]
        #expect(OutlineIdentityMap.remap([], from: some, to: some).isEmpty)
    }

    @Test func insertAboveShiftsTheOldOrdinalForward() {
        // Old: [A(0), B(1) collapsed]. New: [Z(0), A(1), B(2)] — a heading
        // inserted above. B's collapse must follow it to ordinal 2, not stay
        // at 1 (which is now A) and not vanish.
        let old = [
            Fixtures.heading(level: 1, title: "A", line: 1),
            Fixtures.heading(level: 1, title: "B", line: 2),
        ]
        let new = [
            Fixtures.heading(level: 1, title: "Z", line: 1),
            Fixtures.heading(level: 1, title: "A", line: 2),
            Fixtures.heading(level: 1, title: "B", line: 3),
        ]
        let remapped = OutlineIdentityMap.remap([1], from: old, to: new)
        #expect(remapped == [2])
    }

    @Test func deleteAboveShiftsTheOldOrdinalBackward() {
        let old = [
            Fixtures.heading(level: 1, title: "Z", line: 1),
            Fixtures.heading(level: 1, title: "A", line: 2),
            Fixtures.heading(level: 1, title: "B", line: 3),
        ]
        let new = [
            Fixtures.heading(level: 1, title: "A", line: 1),
            Fixtures.heading(level: 1, title: "B", line: 2),
        ]
        let remapped = OutlineIdentityMap.remap([2], from: old, to: new)
        #expect(remapped == [1])
    }

    @Test func editingADifferentHeadingsTextDoesNotDisturbAnUnrelatedID() {
        let old = [
            Fixtures.heading(level: 1, title: "A", line: 1),
            Fixtures.heading(level: 1, title: "B", line: 2),
        ]
        let new = [
            Fixtures.heading(level: 1, title: "A edited", line: 1),
            Fixtures.heading(level: 1, title: "B", line: 2),
        ]
        #expect(OutlineIdentityMap.remap([1], from: old, to: new) == [1])
    }

    @Test func retitlingTheTrackedHeadingDropsItsID() {
        let old = [Fixtures.heading(level: 1, title: "A", line: 1)]
        let new = [Fixtures.heading(level: 1, title: "A renamed", line: 1)]
        #expect(OutlineIdentityMap.remap([0], from: old, to: new).isEmpty)
    }

    @Test func duplicateTitlesResolveToNearestOrdinalAndEachNewOrdinalIsClaimedOnce() {
        // Old: two "Section" headings at ordinals 0 and 2 (with something else
        // at 1). New: three "Section" headings at 0, 1, 2. Old 0 should claim
        // new 0 (nearest), old 2 should claim new 2 (nearest) — not both
        // collapsing onto the same new ordinal.
        let old = [
            Fixtures.heading(level: 1, title: "Section", line: 1),
            Fixtures.heading(level: 1, title: "Other", line: 2),
            Fixtures.heading(level: 1, title: "Section", line: 3),
        ]
        let new = [
            Fixtures.heading(level: 1, title: "Section", line: 1),
            Fixtures.heading(level: 1, title: "Section", line: 2),
            Fixtures.heading(level: 1, title: "Section", line: 3),
        ]
        let remapped = OutlineIdentityMap.remap([0, 2], from: old, to: new)
        #expect(remapped == [0, 2])
    }

    @Test func outOfRangeOldIDIsIgnored() {
        let some = [Fixtures.heading(level: 1, title: "A", line: 1)]
        #expect(OutlineIdentityMap.remap([99], from: some, to: some).isEmpty)
    }

    @Test func singleIDOverloadMirrorsTheSetOverload() {
        let old = [Fixtures.heading(level: 1, title: "A", line: 1)]
        let new = [Fixtures.heading(level: 1, title: "A", line: 1)]
        #expect(OutlineIdentityMap.remap(0, from: old, to: new) == 0)
        #expect(OutlineIdentityMap.remap(Int?.none, from: old, to: new) == nil)
    }
}
