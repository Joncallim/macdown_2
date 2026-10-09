import FileCore
import Foundation
import Testing
@testable import TextSearch

/// Review pass 8: `relativePath.split(separator: "/")` splits on `Character`s, so a `/` followed by a combining mark
/// (a file name starting with U+0301, ZWNJ, VS16…) was never split and the symlinked directory above that file was
/// never checked: Replace in Folder wrote through the link to a file outside the root.
struct WorkspaceReplaceExtendingScalarPathTests {
    @Test(arguments: ["\u{0301}mark.md", "\u{200C}mark.md", "\u{FE0F}mark.md", "\u{200D}mark.md"])
    func anExtendingScalarFileNameIsStillSkippedThroughASymlinkedDirectory(_ name: String) async throws {
        let tree = try WorkspaceSearchEngineTempTree()
        let outside = try WorkspaceSearchEngineTempTree()
        try outside.write(name, text: "foo outside")
        try FileManager.default.createSymbolicLink(
            at: tree.root.appendingPathComponent("dir"),
            withDestinationURL: outside.root
        )
        let snapshot = try FileStore().readSnapshot(from: outside.root.appendingPathComponent(name))
        let plan = ReplacementPlan(
            relativePath: "dir/" + name,
            revision: snapshot.revision,
            matches: [SearchMatch(range: NSRange(location: 0, length: 3))],
            replacementText: "bar"
        )

        let outcomes = await WorkspaceReplaceEngine().replace(root: tree.root, plans: [plan])

        #expect(outcomes.first?.outcome == .skippedSymbolicLink)
        let contents = try String(contentsOf: outside.root.appendingPathComponent(name), encoding: .utf8)
        #expect(contents == "foo outside")
    }
}
