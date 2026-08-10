@testable import FileTree
import Foundation
import Testing

@Test func arrangementFiltersAndFinderSorts() {
    let entries = [
        entry("f10.md"), entry("f2.md"), entry("hidden.md", hidden: true),
        entry("image.png"), entry("folder", directory: true), entry("README"),
    ]
    let result = FileTreeArrangement.arrange(
        entries,
        filter: FileTreeFilter(supportedFilesOnly: true),
        supportedExtensions: ["md"]
    )
    #expect(result.map(\.name) == ["folder", "f2.md", "f10.md"])
}

@Test func diffReportsAttributeChanges() {
    let url = URL(fileURLWithPath: "/tmp/item")
    let old = DirectoryEntry(url: url, isDirectory: false, isHidden: false, isPackage: false, isSymbolicLink: false)
    let new = DirectoryEntry(url: url, isDirectory: true, isHidden: false, isPackage: false, isSymbolicLink: false)
    let diff = FileTreeDiff.diff(old: [old], new: [new])
    #expect(diff.added.isEmpty)
    #expect(diff.removed.isEmpty)
    #expect(diff.changed == [new])
}

@Test func namingAllowsCaseOnlyRenameAndRejectsSibling() {
    #expect(FileTreeNaming.validate("Notes.md", existing: ["notes.md"], currentName: "notes.md") == nil)
    #expect(FileTreeNaming.validate("other.md", existing: ["other.md"], currentName: nil) == .nameExists("other.md"))
}

@Test func tenThousandEntryListingArrangementAndFlatteningBenchmark() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    for index in 0 ..< 10000 {
        guard FileManager.default
            .createFile(atPath: root.appendingPathComponent("item-\(index).md").path, contents: nil)
        else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    let reader = FileSystemDirectoryReader()
    _ = try reader.contents(of: root) // warm metadata and directory-cache path
    let clock = ContinuousClock()
    let start = clock.now
    let listed = try reader.contents(of: root)
    let arranged = FileTreeArrangement.arrange(listed, filter: FileTreeFilter(), supportedExtensions: ["md"])
    let rows = arranged.map { FileTreeRow(entry: $0, depth: 0, isExpanded: false, isLoading: false) }
    let elapsed = start.duration(to: clock.now)

    #expect(rows.count == 10000)
    #if !DEBUG
        #expect(elapsed < .milliseconds(200))
    #endif
}

private func entry(_ name: String, directory: Bool = false, hidden: Bool = false) -> DirectoryEntry {
    DirectoryEntry(
        url: URL(fileURLWithPath: "/tmp/\(name)", isDirectory: directory),
        isDirectory: directory,
        isHidden: hidden,
        isPackage: false,
        isSymbolicLink: false
    )
}
