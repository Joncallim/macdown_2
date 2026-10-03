import Foundation
import Preview
import Testing

/// The editor-to-preview fast path (`ScrollSyncController`) and the public `ScrollSyncMap` must pick the
/// same block for a source line that falls in a gap between blocks. The controller compared the previous
/// block's START, so lines 11-15 went to block 1 there and to block 0 in the map.
@MainActor
struct ScrollSyncGapAgreementTests {
    @Test func controllerAndMapAgreeForEveryLineInAGap() {
        let map = ScrollSyncMap(entries: [
            .init(lineRange: 1 ... 10, blockIndex: 0),
            .init(lineRange: 20 ... 21, blockIndex: 1),
        ])
        let controller = ScrollSyncController(map: map, blockHeights: [0: 100, 1: 20])

        for line in 0 ... 25 {
            #expect(
                map.blockIndex(forLine: line) == controller.blockTarget(forLine: line)?.blockIndex,
                "line \(line)"
            )
        }
    }

    @Test func aLineNearerThePreviousBlocksEndStaysWithThatBlock() {
        let map = ScrollSyncMap(entries: [
            .init(lineRange: 1 ... 10, blockIndex: 0),
            .init(lineRange: 20 ... 21, blockIndex: 1),
        ])
        let controller = ScrollSyncController(map: map, blockHeights: [0: 100, 1: 20])

        #expect(controller.blockTarget(forLine: 12)?.blockIndex == 0)
        #expect(controller.blockTarget(forLine: 18)?.blockIndex == 1)
    }
}
