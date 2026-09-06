import Foundation
@testable import MacDown2
import Testing

@Suite("TextFilterCoordinator range clamping")
struct TextFilterCoordinatorRangeClampingTests {
    @Test func returnsTheSameRangeWhenItIsStillValid() {
        let clamped = TextFilterCoordinator.clampedRange(NSRange(location: 2, length: 3), toLength: 10)
        #expect(clamped == NSRange(location: 2, length: 3))
    }

    @Test func clampsALocationPastTheEndOfShorterText() {
        let clamped = TextFilterCoordinator.clampedRange(NSRange(location: 20, length: 5), toLength: 10)
        #expect(clamped == NSRange(location: 10, length: 0))
    }

    @Test func clampsALengthThatWouldOverrunShorterText() {
        let clamped = TextFilterCoordinator.clampedRange(NSRange(location: 8, length: 10), toLength: 10)
        #expect(clamped == NSRange(location: 8, length: 2))
    }

    @Test func neverProducesANegativeLocationOrLength() {
        let clamped = TextFilterCoordinator.clampedRange(NSRange(location: -5, length: -5), toLength: 10)
        #expect(clamped.location >= 0)
        #expect(clamped.length >= 0)
    }

    @Test func handlesAnEmptyDocument() {
        let clamped = TextFilterCoordinator.clampedRange(NSRange(location: 3, length: 4), toLength: 0)
        #expect(clamped == NSRange(location: 0, length: 0))
    }
}
