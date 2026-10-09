import Darwin
import FileCore
import Foundation
import Testing
@testable import TextSearch

func searchResults(
    _ tree: WorkspaceSearchEngineTempTree,
    query: String,
    options: SearchOptions = SearchOptions()
) async -> [FolderSearchMatch] {
    let index = await tree.makeIndex()
    let box = WorkspaceSearchEngineResultsBox()
    _ = await WorkspaceSearchEngine().search(
        root: tree.root,
        index: index,
        query: query,
        options: options,
        onMatch: { await box.append($0) }
    )
    return await box.all
}

func plans(_ results: [FolderSearchMatch], replacement: String) -> [ReplacementPlan] {
    results.map { ReplacementPlan($0, replacementText: replacement) }
}

func read(_ tree: WorkspaceSearchEngineTempTree, _ path: String) throws -> String {
    try String(contentsOf: tree.root.appendingPathComponent(path), encoding: .utf8)
}

@Suite("WorkspaceReplaceEngine")
struct WorkspaceReplaceEngineTests {
    @Test
    func replacesEveryMatchAcrossFilesEndToEnd() async throws {
        let tree = try WorkspaceSearchEngineTempTree()
        try tree.write("a.md", text: "foo bar foo\nfoo")
        try tree.write("sub/b.md", text: "no match here\nprefix foo suffix")
        try tree.write("untouched.md", text: "nothing")
        let results = await searchResults(tree, query: "foo")

        let outcomes = await WorkspaceReplaceEngine().replace(
            root: tree.root,
            plans: plans(results, replacement: "quux!")
        )

        #expect(outcomes.count == 2)
        #expect(outcomes.allSatisfy {
            if case .replaced = $0.outcome {
                true
            } else {
                false
            }
        })
        #expect(try read(tree, "a.md") == "quux! bar quux!\nquux!")
        #expect(try read(tree, "sub/b.md") == "no match here\nprefix quux! suffix")
        #expect(try read(tree, "untouched.md") == "nothing")
    }

    @Test
    func aMultiLineReplacementAdoptsEachFilesOwnLineEnding() async throws {
        let tree = try WorkspaceSearchEngineTempTree()
        try tree.write("crlf.md", text: "one\r\nfoo\r\ntwo")
        try tree.write("lf.md", text: "one\nfoo\ntwo")
        let results = await searchResults(tree, query: "foo")

        _ = await WorkspaceReplaceEngine().replace(root: tree.root, plans: plans(results, replacement: "a\nb"))

        #expect(try read(tree, "crlf.md") == "one\r\na\r\nb\r\ntwo")
        #expect(try read(tree, "lf.md") == "one\na\nb\ntwo")
    }

    @Test
    func replaceKeepsEachFilesPermissionBits() async throws {
        let tree = try WorkspaceSearchEngineTempTree()
        try tree.write("script.md", text: "foo")
        let path = tree.root.appendingPathComponent("script.md").path
        #expect(chmod(path, 0o700) == 0)
        let results = await searchResults(tree, query: "foo")

        _ = await WorkspaceReplaceEngine().replace(root: tree.root, plans: plans(results, replacement: "bar"))

        #expect(try read(tree, "script.md") == "bar")
        var info = stat()
        #expect(stat(path, &info) == 0)
        #expect(info.st_mode & 0o7777 == 0o700)
    }

    @Test
    func replacementCountsMatchThePlan() async throws {
        let tree = try WorkspaceSearchEngineTempTree()
        try tree.write("a.md", text: "x x x")
        let results = await searchResults(tree, query: "x")
        let outcomes = await WorkspaceReplaceEngine().replace(root: tree.root, plans: plans(results, replacement: "yy"))
        #expect(outcomes.first?.outcome == .replaced(count: 3))
        #expect(try read(tree, "a.md") == "yy yy yy")
    }

    @Test
    func splicesCorrectlyAroundNonBMPCharacters() async throws {
        let tree = try WorkspaceSearchEngineTempTree()
        try tree.write("a.md", text: "😀 foo 😀 foo é")
        let results = await searchResults(tree, query: "foo")
        _ = await WorkspaceReplaceEngine().replace(root: tree.root, plans: plans(results, replacement: "🎉🎉"))
        #expect(try read(tree, "a.md") == "😀 🎉🎉 😀 🎉🎉 é")
    }

    @Test
    func regexMatchesAreReplacedLiterallyWithoutCaptureExpansion() async throws {
        let tree = try WorkspaceSearchEngineTempTree()
        try tree.write("a.md", text: "abc 123")
        var options = SearchOptions()
        options.isRegex = true
        let results = await searchResults(tree, query: "[0-9]+", options: options)
        _ = await WorkspaceReplaceEngine().replace(root: tree.root, plans: plans(results, replacement: "$0\\1"))
        #expect(try read(tree, "a.md") == "abc $0\\1")
    }

    @Test
    func preservesTheFilesEncodingAndBOM() async throws {
        let tree = try WorkspaceSearchEngineTempTree()
        let url = tree.root.appendingPathComponent("u16.md")
        try FileStore().write("hello foo world", to: url, encoding: .utf16LittleEndian, bom: .utf16LittleEndian)
        let results = await searchResults(tree, query: "foo")
        #expect(results.count == 1)

        let outcomes = await WorkspaceReplaceEngine().replace(
            root: tree.root,
            plans: plans(results, replacement: "bar")
        )

        #expect(outcomes.first?.outcome == .replaced(count: 1))
        let snapshot = try FileStore().readSnapshot(from: url)
        #expect(snapshot.text == "hello bar world")
        #expect(snapshot.bom == .utf16LittleEndian)
        #expect(snapshot.encoding == .utf16LittleEndian)
    }

    @Test
    func preservesCRLFLineEndings() async throws {
        let tree = try WorkspaceSearchEngineTempTree()
        try tree.write("a.md", text: "one foo\r\ntwo foo\r\n")
        let results = await searchResults(tree, query: "foo")
        _ = await WorkspaceReplaceEngine().replace(root: tree.root, plans: plans(results, replacement: "bar"))
        #expect(try read(tree, "a.md") == "one bar\r\ntwo bar\r\n")
    }

    @Test
    func aCanonicallyEquivalentButDifferentReplacementIsStillWritten() async throws {
        let tree = try WorkspaceSearchEngineTempTree()
        try tree.write("a.md", text: "x \u{e9} x")
        let nfd = "e\u{301}"
        let results = await searchResults(tree, query: "\u{e9}")
        #expect(results.count == 1)
        _ = await WorkspaceReplaceEngine().replace(root: tree.root, plans: plans(results, replacement: nfd))
        #expect(try read(tree, "a.md").unicodeScalars.elementsEqual("x \(nfd) x".unicodeScalars))
    }

    @Test
    func aReplacementIdenticalToTheMatchDoesNotRewriteTheFile() async throws {
        let tree = try WorkspaceSearchEngineTempTree()
        try tree.write("a.md", text: "foo")
        let url = tree.root.appendingPathComponent("a.md")
        let before = try FileStore().readSnapshot(from: url).revision
        let results = await searchResults(tree, query: "foo")

        let outcomes = await WorkspaceReplaceEngine().replace(
            root: tree.root,
            plans: plans(results, replacement: "foo")
        )

        #expect(outcomes.first?.outcome == .replaced(count: 1))
        #expect(try FileStore().readSnapshot(from: url).revision == before)
    }

    @Test
    func cancellationBetweenFilesLeavesTheRemainderUnattempted() async throws {
        let tree = try WorkspaceSearchEngineTempTree()
        for name in ["a", "b", "c"] {
            try tree.write("\(name).md", text: "foo \(name)")
        }
        let results = await searchResults(tree, query: "foo")
        let counter = CallCounter()
        let root = tree.root
        let replacementPlans = plans(results, replacement: "bar")
        let task = Task { () -> [ReplacementFileResult] in
            var seams = WorkspaceReplaceEngine.TestSeams()
            seams.beforeEachFile = {
                if await counter.next() == 2 {
                    withUnsafeCurrentTask { $0?.cancel() }
                }
            }
            return await WorkspaceReplaceEngine(seams: seams).replace(root: root, plans: replacementPlans)
        }
        let outcomes = await task.value

        #expect(outcomes.map(\.outcome) == [.replaced(count: 1), .notAttempted, .notAttempted])
        for (position, result) in outcomes.enumerated() {
            let name = String(result.relativePath.dropLast(3))
            #expect(try read(tree, result.relativePath) == (position == 0 ? "bar \(name)" : "foo \(name)"))
        }
    }
}

private actor CallCounter {
    private var value = 0
    func next() -> Int {
        value += 1
        return value
    }
}

@Suite("WorkspaceReplaceEngine preview")
struct WorkspaceReplacePreviewTests {
    private func preview(
        _ tree: WorkspaceSearchEngineTempTree,
        query: String,
        replacement: String,
        options: SearchOptions = SearchOptions(),
        path: String = "a.md"
    ) async throws -> ReplacementFilePreview {
        let results = await searchResults(tree, query: query, options: options)
        let match = try #require(results.first { $0.relativePath == path })
        return await WorkspaceReplaceEngine().preview(
            root: tree.root,
            plan: ReplacementPlan(match, replacementText: replacement)
        )
    }

    @Test
    func showsLineNumbersAndBeforeAfterForEachAffectedLine() async throws {
        let tree = try WorkspaceSearchEngineTempTree()
        try tree.write("a.md", text: "alpha\nfoo one foo\nbeta\nfoo two\n")
        let result = try await preview(tree, query: "foo", replacement: "X")
        #expect(result == .lines([
            ReplacementPreviewLine(lineNumber: 2, before: "foo one foo", after: "X one X"),
            ReplacementPreviewLine(lineNumber: 4, before: "foo two", after: "X two"),
        ], totalRegionCount: 2))
    }

    @Test
    func lineNumbersAccountForCRLFAndLoneCR() async throws {
        let tree = try WorkspaceSearchEngineTempTree()
        try tree.write("a.md", text: "a\r\nb\rfoo\r\nc foo")
        let result = try await preview(tree, query: "foo", replacement: "X")
        guard case let .lines(lines, total) = result else { Issue.record("no lines"); return }
        #expect(lines.map(\.lineNumber) == [3, 4])
        #expect(lines.map(\.before) == ["foo", "c foo"])
        #expect(total == 2)
    }

    @Test
    func aMultiLineMatchIsOneRegionCoveringEveryLineItSpans() async throws {
        let tree = try WorkspaceSearchEngineTempTree()
        try tree.write("a.md", text: "x\nfoo\nbar\ny")
        var options = SearchOptions()
        options.isRegex = true
        let result = try await preview(tree, query: "foo\\nbar", replacement: "Z", options: options)
        #expect(result == .lines(
            [ReplacementPreviewLine(lineNumber: 2, before: "foo\nbar", after: "Z")],
            totalRegionCount: 1
        ))
    }

    @Test
    func theLineListIsCappedButTheTotalIsExact() async throws {
        let tree = try WorkspaceSearchEngineTempTree()
        try tree.write("a.md", text: (0 ..< 12).map { "foo \($0)" }.joined(separator: "\n"))
        let result = try await preview(tree, query: "foo", replacement: "X")
        guard case let .lines(lines, total) = result else { Issue.record("no lines"); return }
        #expect(lines.count == WorkspaceReplaceEngine.previewLineLimit)
        #expect(total == 12)
        #expect(lines.map(\.lineNumber) == Array(1 ... WorkspaceReplaceEngine.previewLineLimit))
    }

    @Test
    func aVeryLongLineIsWindowedAroundTheFirstMatch() async throws {
        let tree = try WorkspaceSearchEngineTempTree()
        let line = String(repeating: "a", count: 5000) + "foo" + String(repeating: "b", count: 5000)
        try tree.write("a.md", text: line)
        let result = try await preview(tree, query: "foo", replacement: "X")
        guard case let .lines(lines, _) = result, let first = lines.first else { Issue.record("no lines"); return }
        #expect(first.before.count <= WorkspaceReplaceEngine.previewRegionCharacterLimit + 2)
        #expect(first.before.contains("foo"))
        #expect(first.after.contains("X") && !first.after.contains("foo"))
        #expect(first.before.hasPrefix("…") && first.before.hasSuffix("…"))
    }

    @Test
    func aFileChangedSinceTheSearchPreviewsAsChanged() async throws {
        let tree = try WorkspaceSearchEngineTempTree()
        try tree.write("a.md", text: "foo")
        let results = await searchResults(tree, query: "foo")
        try tree.write("a.md", text: "foo!")
        let result = await WorkspaceReplaceEngine().preview(
            root: tree.root,
            plan: ReplacementPlan(results[0], replacementText: "X")
        )
        #expect(result == .changedSinceSearch)
    }

    @Test
    func previewingNeverModifiesTheFile() async throws {
        let tree = try WorkspaceSearchEngineTempTree()
        try tree.write("a.md", text: "foo")
        _ = try await preview(tree, query: "foo", replacement: "X")
        #expect(try read(tree, "a.md") == "foo")
    }
}
