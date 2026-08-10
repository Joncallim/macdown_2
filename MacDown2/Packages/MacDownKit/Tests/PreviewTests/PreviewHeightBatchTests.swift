import Foundation
@testable import Preview
import Testing

@Suite("Preview height batching")
@MainActor
struct PreviewHeightBatchTests {
    @Test func publishesOneLatestSnapshotForManyGeometryCallbacks() {
        let controller = ScrollSyncController()
        let batch = PreviewHeightBatch()

        batch.record(10, for: 0, controller: controller)
        batch.record(20, for: 1, controller: controller)
        batch.record(12, for: 0, controller: controller)

        // No mutable SwiftUI state is replaced for each callback. The view
        // publishes the accumulated immutable snapshot at its batch boundary.
        #expect(controller.blockHeights.isEmpty)
        batch.flush(to: controller)
        #expect(controller.blockHeights == [0: 12, 1: 20])
    }

    @Test func retainingBlocksDropsOnlyTheRemovedTail() {
        let controller = ScrollSyncController()
        let batch = PreviewHeightBatch()
        batch.record(10, for: 0, controller: controller)
        batch.record(20, for: 1, controller: controller)
        batch.record(30, for: 2, controller: controller)
        batch.flush(to: controller)

        batch.retainEntries(before: 2, controller: controller)

        #expect(controller.blockHeights == [0: 10, 1: 20])
    }

    @Test func reconcilesMeasuredHeightsByStableBlockIdentity() {
        let firstID = UUID()
        let secondID = UUID()
        let first = PreviewBlock(id: firstID, kind: .paragraph, source: "first", lineRange: 1 ... 1)
        let second = PreviewBlock(id: secondID, kind: .paragraph, source: "second", lineRange: 3 ... 3)
        let controller = ScrollSyncController()
        let batch = PreviewHeightBatch()

        batch.record(10, for: firstID, at: 0, controller: controller)
        batch.record(20, for: secondID, at: 1, controller: controller)
        batch.flush(to: controller)
        batch.reconcile(with: [second, first], controller: controller)

        #expect(controller.blockHeights == [0: 20, 1: 10])
    }
}
