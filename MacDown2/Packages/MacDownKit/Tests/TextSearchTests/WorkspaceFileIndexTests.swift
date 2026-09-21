import Foundation
import Testing
@testable import TextSearch

@Suite("WorkspaceFileIndex")
struct WorkspaceFileIndexTests {
    /// A real temporary directory tree, torn down after the test.
    private final class TempTree {
        let root: URL

        init(_ build: (URL) throws -> Void) throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try build(root)
        }

        deinit {
            try? FileManager.default.removeItem(at: root)
        }

        func write(_ relativePath: String) throws {
            let url = root.appendingPathComponent(relativePath)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data().write(to: url)
        }
    }

    @Test func indexesRegularFilesRecursively() async throws {
        let tree = try TempTree { root in
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }
        try tree.write("a.txt")
        try tree.write("sub/b.txt")
        try tree.write("sub/nested/c.txt")

        let index = WorkspaceFileIndex()
        await index.rebuild(root: tree.root)
        let results = await index.query("")
        #expect(Set(results.map(\.relativePath)) == ["a.txt", "sub/b.txt", "sub/nested/c.txt"])
    }

    @Test func excludesDefaultDirectories() async throws {
        let tree = try TempTree { _ in }
        try tree.write("keep.txt")
        try tree.write(".git/HEAD")
        try tree.write("node_modules/pkg/index.js")

        let index = WorkspaceFileIndex()
        await index.rebuild(root: tree.root)
        let results = await index.query("")
        #expect(results.map(\.relativePath) == ["keep.txt"])
    }

    @Test func excludesHiddenFiles() async throws {
        let tree = try TempTree { _ in }
        try tree.write("visible.txt")
        try tree.write(".hidden")

        let index = WorkspaceFileIndex()
        await index.rebuild(root: tree.root)
        let results = await index.query("")
        #expect(results.map(\.relativePath) == ["visible.txt"])
    }

    @Test func queryRanksFuzzyMatches() async throws {
        let tree = try TempTree { _ in }
        try tree.write("WindowCoordinator.swift")
        try tree.write("unrelated.swift")

        let index = WorkspaceFileIndex()
        await index.rebuild(root: tree.root)
        let results = await index.query("wico")
        #expect(results.first?.relativePath == "WindowCoordinator.swift")
    }

    @Test func queryLimitCapsResults() async throws {
        let tree = try TempTree { _ in }
        for index in 0 ..< 20 {
            try tree.write("file\(index).txt")
        }

        let index = WorkspaceFileIndex()
        await index.rebuild(root: tree.root)
        let results = await index.query("file", limit: 5)
        #expect(results.count == 5)
    }

    @Test func symlinkLoopDoesNotHang() async throws {
        let tree = try TempTree { root in
            let looped = root.appendingPathComponent("looped", isDirectory: true)
            try FileManager.default.createDirectory(at: looped, withIntermediateDirectories: true)
            // A symlink inside `looped` pointing back to `looped` itself.
            try FileManager.default.createSymbolicLink(
                at: looped.appendingPathComponent("self"),
                withDestinationURL: looped
            )
        }
        try tree.write("real.txt")

        let index = WorkspaceFileIndex()
        // The real assertion is that this call returns at all (a symlink
        // loop with no guard would recurse forever).
        await index.rebuild(root: tree.root)
        let results = await index.query("")
        #expect(results.contains { $0.relativePath == "real.txt" })
    }

    @Test func rapidSupersedingRebuildsSettleOnTheLastRootWithoutCorruption() async throws {
        let treeA = try TempTree { _ in }
        try treeA.write("a1.txt")
        try treeA.write("a2.txt")

        let treeB = try TempTree { _ in }
        try treeB.write("b1.txt")

        let index = WorkspaceFileIndex()
        // A rebuild for `treeB` fires before `treeA`'s rebuild finishes: the
        // superseded walk's own task is cancelled, and its result (even if
        // it completes anyway) must never overwrite the newer one's.
        async let first: Void = index.rebuild(root: treeA.root)
        async let second: Void = index.rebuild(root: treeB.root)
        _ = await (first, second)

        let results = await index.query("")
        #expect(Set(results.map(\.relativePath)) == ["b1.txt"])
    }

    @Test func stateReflectsBuildProgress() async throws {
        let tree = try TempTree { _ in }
        try tree.write("a.txt")

        let index = WorkspaceFileIndex()
        let initialState = await index.state
        #expect(initialState == .empty)

        await index.rebuild(root: tree.root)
        let finalState = await index.state
        #expect(finalState == .ready(count: 1))
    }
}
