import Foundation
import Testing
@testable import TextSearch

@Suite("WorkspaceSearchEngine index failure")
struct WorkspaceSearchEngineIndexFailureTests {
    /// #183 F18: a failed index (vanished root) is reported as such, not as a
    /// search that merely found nothing.
    @Test func aFailedIndexIsReportedAsUnavailableNotAsNoResults() async throws {
        let tree = try WorkspaceSearchEngineTempTree()
        try tree.write("a.txt", text: "hello")
        let index = await tree.makeIndex()
        try FileManager.default.removeItem(at: tree.root)
        await index.rebuild(root: tree.root)

        let (outcome, results) = await runFolderSearch(root: tree.root, index: index, query: "hello")

        #expect(outcome == .indexUnavailable)
        #expect(results.isEmpty)
    }
}
