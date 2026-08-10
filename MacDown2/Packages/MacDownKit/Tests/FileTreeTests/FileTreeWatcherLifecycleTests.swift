@testable import FileTree
import Foundation
import Testing

@MainActor
@Test func renamingTheRootRestartsItsLoadedRootWatcher() async {
    let root = URL(fileURLWithPath: "/tmp/root-before-rename", isDirectory: true)
    let renamed = URL(fileURLWithPath: "/tmp/root-after-rename", isDirectory: true)
    let watcher = RecordingWatching()
    let model = FileTreeModel(
        reader: StaticReader(contents: [root: [], renamed: []]),
        watcher: watcher,
        preferences: FileTreePreferences(store: MemoryPreferenceStore()),
        supportedExtensions: ["md"]
    )

    await model.setRoot(root)
    model.itemWasRenamed(from: root, to: renamed)

    #expect(model.root == renamed.standardizedFileURL)
    #expect(model.watchedDirectoryCount == 1)
    #expect(watcher.activeCount == 1)
    #expect(watcher.totalWatchCount == 2)
}

@MainActor
@Test func watcherCountStaysBoundedThroughCollapseChurnAndTearDown() async {
    let root = URL(fileURLWithPath: "/tmp/watcher-churn", isDirectory: true)
    let parent = root.appendingPathComponent("parent", isDirectory: true)
    let child = parent.appendingPathComponent("child", isDirectory: true)
    let watcher = RecordingWatching()
    let model = FileTreeModel(
        reader: StaticReader(contents: [
            root: [directory(parent)],
            parent: [directory(child)],
            child: [],
        ]),
        watcher: watcher,
        preferences: FileTreePreferences(store: MemoryPreferenceStore()),
        supportedExtensions: ["md"]
    )

    await model.setRoot(root)
    for _ in 0 ..< 10 {
        await model.expand(parent)
        await model.expand(child)
        #expect(model.watchedDirectoryCount == 3)
        #expect(watcher.activeCount == 3)

        model.collapse(child)
        model.collapse(parent)
        #expect(model.watchedDirectoryCount == 1)
        #expect(watcher.activeCount == 1)
    }

    model.tearDown()
    #expect(model.watchedDirectoryCount == 0)
    #expect(watcher.activeCount == 0)
}
