import Foundation
import Testing
@testable import Workspace

@MainActor
@Suite("SidebarSection reconcile")
struct SidebarSectionOrderTests {
    @Test func reconcileEmptyReturnsDefaultOrder() {
        let order = SidebarSection.reconcile([])
        #expect(order == SidebarSection.defaultOrder)
    }

    @Test func reconcileIgnoresUnknownIDs() {
        let order = SidebarSection.reconcile(["unknown", "folder"])
        #expect(order == [.folder, .outline])
    }

    @Test func reconcileDeduplicatesIDs() {
        let order = SidebarSection.reconcile(["folder", "folder", "outline", "outline"])
        #expect(order == [.folder, .outline])
    }

    @Test func reconcileAppendsMissingCases() {
        let order = SidebarSection.reconcile(["outline"])
        #expect(order == [.outline, .folder])
    }

    @Test func reconcilePreservesPartialReverse() {
        let order = SidebarSection.reconcile(["outline", "folder"])
        #expect(order == [.outline, .folder])
    }

    @Test func reconcileIsIdempotent() {
        let input = ["outline", "folder"]
        let first = SidebarSection.reconcile(input)
        let second = SidebarSection.reconcile(first.map(\.rawValue))
        #expect(first == second)
    }
}

/// `SidebarSection` only has two cases today, so the `onMove` offset
/// convention — where `toOffset` is an insertion point in the *pre-move*
/// ordering — is only observable on three or more elements. These exercise
/// `reorder` directly so a future third section inherits correct behavior.
@Suite("reorder(_:fromOffsets:toOffset:)")
struct ReorderTests {
    private struct ReorderCase: Sendable {
        let name: String
        let elements: [String]
        let offsets: IndexSet
        let offset: Int
        let expected: [String]
    }

    @Test(arguments: [
        ReorderCase(
            name: "first item dropped between the other two",
            elements: ["a", "b", "c"],
            offsets: IndexSet(integer: 0),
            offset: 2,
            expected: ["b", "a", "c"]
        ),
        ReorderCase(
            name: "first item dropped past the end",
            elements: ["a", "b", "c"],
            offsets: IndexSet(integer: 0),
            offset: 3,
            expected: ["b", "c", "a"]
        ),
        ReorderCase(
            name: "last item dropped at the front",
            elements: ["a", "b", "c"],
            offsets: IndexSet(integer: 2),
            offset: 0,
            expected: ["c", "a", "b"]
        ),
        ReorderCase(
            name: "contiguous pair dropped after the remainder",
            elements: ["a", "b", "c"],
            offsets: IndexSet([0, 1]),
            offset: 3,
            expected: ["c", "a", "b"]
        ),
        ReorderCase(
            name: "discontiguous pair keeps source order",
            elements: ["a", "b", "c", "d"],
            offsets: IndexSet([0, 2]),
            offset: 4,
            expected: ["b", "d", "a", "c"]
        ),
        ReorderCase(
            name: "drop onto own position is a no-op",
            elements: ["a", "b", "c"],
            offsets: IndexSet(integer: 1),
            offset: 1,
            expected: ["a", "b", "c"]
        ),
        ReorderCase(
            name: "out-of-range source index ignored",
            elements: ["a", "b", "c"],
            offsets: IndexSet(integer: 99),
            offset: 0,
            expected: ["a", "b", "c"]
        ),
        ReorderCase(
            name: "negative destination clamps to the front",
            elements: ["a", "b", "c"],
            offsets: IndexSet(integer: 2),
            offset: -5,
            expected: ["c", "a", "b"]
        ),
        ReorderCase(
            name: "destination past the end clamps to the back",
            elements: ["a", "b", "c"],
            offsets: IndexSet(integer: 0),
            offset: 99,
            expected: ["b", "c", "a"]
        ),
        ReorderCase(
            name: "empty collection tolerates any drag",
            elements: [],
            offsets: IndexSet(integer: 0),
            offset: 3,
            expected: []
        ),
    ])
    private func reorderMatchesOnMoveConvention(_ testCase: ReorderCase) {
        let result = reorder(
            testCase.elements,
            fromOffsets: testCase.offsets,
            toOffset: testCase.offset
        )
        #expect(result == testCase.expected, "Test case: \(testCase.name)")
    }
}
