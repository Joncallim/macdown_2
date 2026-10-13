@testable import MacDown2
import Testing

@Suite("Folder-search request ownership")
struct FolderSearchRequestGateTests {
    @Test func newerRequestForTheSameFileSupersedesOlderRequest() {
        var gate = FolderSearchRequestGate()
        let first = gate.begin(for: "/tmp/document.md")
        let second = gate.begin(for: "/tmp/document.md")

        #expect(second != first)
        #expect(!gate.owns(first, for: "/tmp/document.md"))
        #expect(gate.owns(second, for: "/tmp/document.md"))
    }

    @Test func requestsForDifferentFilesRemainIndependent() {
        var gate = FolderSearchRequestGate()
        let first = gate.begin(for: "/tmp/first.md")
        let second = gate.begin(for: "/tmp/second.md")

        #expect(gate.owns(first, for: "/tmp/first.md"))
        #expect(gate.owns(second, for: "/tmp/second.md"))
    }
}
