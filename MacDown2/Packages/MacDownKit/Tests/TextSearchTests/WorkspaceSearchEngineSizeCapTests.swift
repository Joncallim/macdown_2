import Foundation
import Testing
@testable import TextSearch

@Suite("WorkspaceSearchEngine size cap")
struct WorkspaceSearchEngineSizeCapTests {
    /// A sparse 40 MB file stands in for a video or disk image: it must be skipped without being read.
    @Test func aFileAboveTheSizeCapIsSkippedWithoutBeingRead() async throws {
        let tree = try WorkspaceSearchEngineTempTree()
        try tree.write("small.txt", text: "hello")
        let big = tree.root.appendingPathComponent("big.txt")
        try "hello".write(to: big, atomically: true, encoding: .utf8)
        let handle = try FileHandle(forWritingTo: big)
        try handle.truncate(atOffset: UInt64(WorkspaceSearchEngine.maximumSearchableFileSize) + 8 * 1024 * 1024)
        try handle.close()
        let index = await tree.makeIndex()

        let (outcome, results) = await runFolderSearch(root: tree.root, index: index, query: "hello")

        #expect(outcome == .completed(filesSearched: 1, filesSkipped: 1, matchCount: 1))
        #expect(results.map(\.relativePath) == ["small.txt"])
    }
}
