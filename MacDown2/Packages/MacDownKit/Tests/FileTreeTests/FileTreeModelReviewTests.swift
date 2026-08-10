@testable import FileTree
import Foundation
import Testing

@MainActor
@Test func replacingRootWhileTheOldReaderIsSuspendedCannotInstallAnOldWatcher() async {
    let oldRoot = URL(fileURLWithPath: "/tmp/old-root", isDirectory: true)
    let newRoot = URL(fileURLWithPath: "/tmp/new-root", isDirectory: true)
    let reader = BlockingReader(blockedURL: oldRoot)
    let model = FileTreeModel(
        reader: reader,
        watcher: TestWatching(),
        preferences: FileTreePreferences(store: MemoryPreferenceStore()),
        supportedExtensions: ["md"]
    )

    let firstSetRoot = Task { await model.setRoot(oldRoot) }
    for _ in 0 ..< 1000 where !reader.didStart {
        await Task.yield()
    }
    #expect(reader.didStart)
    await model.setRoot(newRoot)
    reader.release.signal()
    await firstSetRoot.value

    #expect(model.root == newRoot.standardizedFileURL)
    #expect(model.watchedDirectoryCount == 1)
}

@MainActor
@Test func renamingAnExpandedSubtreeRekeysRowsAndRestartsItsWatchers() async {
    let root = URL(fileURLWithPath: "/tmp/tree-root", isDirectory: true)
    let firstDirectory = root.appendingPathComponent("a", isDirectory: true)
    let nestedDirectory = firstDirectory.appendingPathComponent("b", isDirectory: true)
    let nestedFile = nestedDirectory.appendingPathComponent("c.md")
    let reader = StaticReader(contents: [
        root: [directory(firstDirectory)],
        firstDirectory: [directory(nestedDirectory)],
        nestedDirectory: [file(nestedFile)],
    ])
    let model = FileTreeModel(
        reader: reader,
        watcher: TestWatching(),
        preferences: FileTreePreferences(store: MemoryPreferenceStore()),
        supportedExtensions: ["md"]
    )

    await model.setRoot(root)
    await model.expand(firstDirectory)
    await model.expand(nestedDirectory)
    let renamed = root.appendingPathComponent("z", isDirectory: true)
    model.itemWasRenamed(from: firstDirectory, to: renamed)

    #expect(model.rows.map(\.entry.url.path) == [
        renamed.path,
        renamed.appendingPathComponent("b", isDirectory: true).path,
        renamed.appendingPathComponent("b/c.md").path,
    ])
    #expect(model.watchedDirectoryCount == 3)
}

@MainActor
@Test func sharedPreferencesRebuildEverySubscribedModel() async {
    let root = URL(fileURLWithPath: "/tmp/preferences-root", isDirectory: true)
    let contents: [URL: [DirectoryEntry]] = [
        root: [
            file(root.appendingPathComponent("keep.md")),
            file(root.appendingPathComponent("hide.png")),
        ],
    ]
    let reader = StaticReader(contents: contents)
    let preferences = FileTreePreferences(store: MemoryPreferenceStore())
    let first = FileTreeModel(
        reader: reader,
        watcher: TestWatching(),
        preferences: preferences,
        supportedExtensions: ["md"]
    )
    let second = FileTreeModel(
        reader: reader,
        watcher: TestWatching(),
        preferences: preferences,
        supportedExtensions: ["md"]
    )
    first.startObservingPreferences()
    second.startObservingPreferences()
    await first.setRoot(root)
    await second.setRoot(root)

    preferences.filter = FileTreeFilter(supportedFilesOnly: true)

    #expect(first.rows.map(\.entry.name) == ["keep.md"])
    #expect(second.rows.map(\.entry.name) == ["keep.md"])
}

@Test func directoryEntriesKeepDirectoryIdentityWhileDiffUsesPhysicalPath() {
    let path = URL(fileURLWithPath: "/tmp/item")
    let fileEntry = DirectoryEntry(
        url: path,
        isDirectory: false,
        isHidden: false,
        isPackage: false,
        isSymbolicLink: false
    )
    let directoryEntry = DirectoryEntry(
        url: path,
        isDirectory: true,
        isHidden: false,
        isPackage: false,
        isSymbolicLink: false
    )

    #expect(directoryEntry.url.hasDirectoryPath)
    #expect(FileTreeDiff.diff(old: [fileEntry], new: [directoryEntry]).changed == [directoryEntry])
}

@MainActor
@Test func externalCopyLeavesTheFinderSourceInPlace() async throws {
    let root = temporaryDirectory()
    let external = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: external) }
    let source = external.appendingPathComponent("import.md")
    try Data("imported".utf8).write(to: source)
    let model = FileTreeModel(
        watcher: TestWatching(),
        preferences: FileTreePreferences(store: MemoryPreferenceStore()),
        supportedExtensions: ["md"]
    )

    await model.setRoot(root)
    let copied = try await model.copyExternal(source, intoDirectory: root)

    #expect(FileManager.default.fileExists(atPath: source.path))
    #expect(FileManager.default.fileExists(atPath: copied.url.path))
    #expect(try Data(contentsOf: copied.url) == Data("imported".utf8))
}

@Test func directoryReaderKeepsSymlinkPathAndClassifiesDirectoryTargets() throws {
    let root = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let target = root.appendingPathComponent("target", isDirectory: true)
    let link = root.appendingPathComponent("linked", isDirectory: true)
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

    let entry = try #require(FileSystemDirectoryReader().contents(of: root).first { $0.name == "linked" })
    #expect(entry.isSymbolicLink)
    #expect(entry.isDirectory)
    #expect(entry.url.path == link.path)
}

@MainActor
@Test func expandingASymlinkedDirectoryListsItsTargetThroughLexicalChildURLs() async throws {
    let root = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let target = root.appendingPathComponent("target", isDirectory: true)
    let child = target.appendingPathComponent("child.md")
    let link = root.appendingPathComponent("linked", isDirectory: true)
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    try Data().write(to: child)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

    let model = FileTreeModel(
        watcher: TestWatching(),
        preferences: FileTreePreferences(store: MemoryPreferenceStore()),
        supportedExtensions: ["md"]
    )
    await model.setRoot(root)
    await model.expand(link)

    #expect(model.rows.map(\.entry.url.path).contains(link.appendingPathComponent("child.md").path))
    #expect(!model.rows.map(\.entry.url.path).contains(target.appendingPathComponent("child.md").path))
}

@Test func brokenSymlinkIsAFileSystemObjectForCRUDPreflight() async throws {
    let root = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let link = root.appendingPathComponent("broken")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root.appendingPathComponent("missing"))

    #expect(try await FileSystemMutator().itemKind(at: link) == .file)
}

@MainActor
@Test func externalDirectoryCopyRejectsSelfAndDescendantWithoutMutatingSource() async throws {
    let root = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let nested = root.appendingPathComponent("nested", isDirectory: true)
    let marker = root.appendingPathComponent("marker.md")
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
    try Data("keep".utf8).write(to: marker)
    let model = FileTreeModel(
        watcher: TestWatching(),
        preferences: FileTreePreferences(store: MemoryPreferenceStore()),
        supportedExtensions: ["md"]
    )

    await model.setRoot(root)
    await #expect(throws: FileTreeOperationError.moveIntoOwnSubtree) {
        try await model.copyExternal(root, intoDirectory: root)
    }
    await #expect(throws: FileTreeOperationError.moveIntoOwnSubtree) {
        try await model.copyExternal(root, intoDirectory: nested)
    }
    #expect(try Data(contentsOf: marker) == Data("keep".utf8))
    #expect(!FileManager.default.fileExists(atPath: nested.appendingPathComponent(root.lastPathComponent).path))
}

@MainActor
@Test func failedChildExpansionCanBeRetriedWithoutHidingSiblingRows() async {
    let root = URL(fileURLWithPath: "/tmp/retry-root", isDirectory: true)
    let failing = root.appendingPathComponent("failing", isDirectory: true)
    let sibling = root.appendingPathComponent("sibling.md")
    let reader = FlakyReader(root: root, child: failing, sibling: sibling)
    let model = FileTreeModel(
        reader: reader,
        watcher: TestWatching(),
        preferences: FileTreePreferences(store: MemoryPreferenceStore()),
        supportedExtensions: ["md"]
    )

    await model.setRoot(root)
    await model.expand(failing)
    #expect(model.rows.first(where: { $0.entry.url == failing })?.loadError != nil)
    #expect(model.rows.contains { $0.entry.url == sibling })

    await model.expand(failing)
    #expect(model.rows.first(where: { $0.entry.url == failing })?.loadError == nil)
    #expect(model.rows.contains { $0.entry.name == "recovered.md" })
}

@MainActor
@Test func unreadableRootKeepsItsScopeAndCanBeRescanned() async {
    let root = URL(fileURLWithPath: "/tmp/retry-root-read", isDirectory: true)
    let model = FileTreeModel(
        reader: RootFlakyReader(root: root),
        watcher: TestWatching(),
        preferences: FileTreePreferences(store: MemoryPreferenceStore()),
        supportedExtensions: ["md"]
    )

    await model.setRoot(root)
    if case .rootUnreadable = model.availability {} else {
        Issue.record("Expected retryable unreadable root")
    }
    await model.rescanExpandedDirectories()
    #expect(model.availability == .empty)
    #expect(model.root == root.standardizedFileURL)
}

@Test func fileMutatorThrowsWhenCreateCannotCreateAnExistingFile() async throws {
    let root = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("missing-parent/exists.md")
    let mutator = FileSystemMutator()

    await #expect(throws: (any Error).self) {
        try await mutator.createFile(at: file)
    }
}

@Test func exclusiveFileCreationPreservesRaceCreatedBytes() async throws {
    let root = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("untitled.md")
    let original = Data("race winner".utf8)
    try original.write(to: file)

    await #expect(throws: POSIXError.self) {
        try await FileSystemMutator().createFile(at: file)
    }
    #expect(try Data(contentsOf: file) == original)
}

@MainActor
@Test func modelRetriesExclusiveCreationWithoutTruncatingRaceWinner() async throws {
    let root = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let mutator = RaceCreatingMutator()
    let model = FileTreeModel(
        reader: StaticReader(contents: [root: []]),
        mutator: mutator,
        watcher: TestWatching(),
        preferences: FileTreePreferences(store: MemoryPreferenceStore()),
        supportedExtensions: ["md"]
    )
    await model.setRoot(root)
    let created = try await model.createFile(in: root)

    #expect(created.url.lastPathComponent == "untitled 2.md")
    #expect(try Data(contentsOf: root.appendingPathComponent("untitled.md")) == Data("race winner".utf8))
}

@MainActor
@Test func modelRetriesFolderCreationAfterCocoaFileExistsRace() async throws {
    let root = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let mutator = FolderRaceMutator()
    let model = FileTreeModel(
        reader: StaticReader(contents: [root: []]),
        mutator: mutator,
        watcher: TestWatching(),
        preferences: FileTreePreferences(store: MemoryPreferenceStore()),
        supportedExtensions: ["md"]
    )
    await model.setRoot(root)

    let created = try await model.createFolder(in: root)
    #expect(created.url.lastPathComponent == "untitled 2")
    #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("untitled").path))
}

@Test func copySafetyDetectsCaseAndUnicodeEquivalentDirectoryAliasesWhenSupported() throws {
    let root = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let directory = root.appendingPathComponent("Cafe\u{301}", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let caseAlias = root.appendingPathComponent("CAFÉ", isDirectory: true)
    if FileManager.default.fileExists(atPath: caseAlias.path) {
        #expect(try FileTreeCopySafety
            .validateDirectoryCopy(source: directory, intoDirectory: caseAlias) == .moveIntoOwnSubtree)
    }
}

@Test func copySafetyAllowsUnrelatedSiblingDirectory() throws {
    let root = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("source", isDirectory: true)
    let destination = root.appendingPathComponent("destination", isDirectory: true)
    try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

    #expect(try FileTreeCopySafety.validateDirectoryCopy(source: source, intoDirectory: destination) == nil)
}

@Test func symlinkDirectoryDestinationHasDirectoryMutationKind() async throws {
    let root = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let target = root.appendingPathComponent("target", isDirectory: true)
    let link = root.appendingPathComponent("link", isDirectory: true)
    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

    #expect(try await FileSystemMutator().itemKind(at: link) == .directory)
}
