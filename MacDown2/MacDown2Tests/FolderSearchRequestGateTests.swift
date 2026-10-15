@testable import MacDown2
import Testing

@Suite("Folder-search request ownership")
struct FolderSearchRequestGateTests {
    @Test func newerRequestForTheSameFileSupersedesOlderRequest() {
        var gate = FolderSearchRequestGate()
        let first = gate.begin()
        let second = gate.begin()

        #expect(second != first)
        #expect(!gate.owns(first))
        #expect(gate.owns(second))
    }

    @Test func newerRequestForAnotherFileAlsoSupersedesOlderRequest() {
        var gate = FolderSearchRequestGate()
        let first = gate.begin()
        let second = gate.begin()

        #expect(!gate.owns(first))
        #expect(gate.owns(second))
    }
}
