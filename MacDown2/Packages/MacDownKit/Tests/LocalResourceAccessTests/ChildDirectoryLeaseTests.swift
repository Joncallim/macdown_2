import Darwin
import Foundation
@testable import LocalResourceAccess
import Testing

/// A child directory must be pinned beneath an already granted root, including when names move around the syscall.
@Suite(.serialized)
struct ChildDirectoryLeaseTests {
    @Test func nestedChildKeepsDocumentRelativeReadsInsideItsOwnBase() throws {
        let tree = try ResourceTestSupport.makeTree()
        defer { tree.cleanup() }
        try tree.write("document-image", to: "chapter/images/plot.txt")
        try tree.write("sibling-image", to: "other/images/plot.txt")
        let root = try DirectoryLease(opening: tree.root)
        defer { root.close() }
        let child = try root.childDirectory(ResourceTestSupport.reference("chapter"))
        defer { child.close() }

        let snapshot = try ContainedResourceReader.read(
            ResourceTestSupport.reference("images/plot.txt"), in: child, maxBytes: 1024
        )
        #expect(snapshot.bytes == Data("document-image".utf8))
        #expect(throws: ResourceReadError.denied) {
            try ContainedResourceReader.read(
                ResourceReference(components: ["..", "other", "images", "plot.txt"]),
                in: child, maxBytes: 1024
            )
        }
    }

    @Test func anInRootDirectorySymlinkCanResolveButAnOutsideOneCannot() throws {
        let tree = try ResourceTestSupport.makeTree()
        defer { tree.cleanup() }
        try tree.write("inside", to: "real/picture.txt")
        try FileManager.default.createSymbolicLink(
            atPath: tree.root.appendingPathComponent("alias").path, withDestinationPath: "real"
        )
        try FileManager.default.createSymbolicLink(
            at: tree.root.appendingPathComponent("escape"), withDestinationURL: tree.outside
        )
        let root = try DirectoryLease(opening: tree.root)
        defer { root.close() }
        let child = try root.childDirectory(ResourceTestSupport.reference("alias"))
        defer { child.close() }

        #expect(try ContainedResourceReader.read(
            ResourceTestSupport.reference("picture.txt"), in: child, maxBytes: 1024
        ).bytes == Data("inside".utf8))
        #expect(throws: ResourceReadError.denied) {
            try root.childDirectory(ResourceTestSupport.reference("escape"))
        }
    }

    @Test func anOrdinaryChildReplacementBeforeTheRealOpenCannotBecomeTheDocumentBase() throws {
        let tree = try ResourceTestSupport.makeTree()
        defer { tree.cleanup() }
        try tree.write("ORIGINAL", to: "chapter/image.txt")
        try tree.write("REPLACEMENT", to: "replacement/image.txt")
        let root = try DirectoryLease(opening: tree.root)
        defer { root.close() }
        let chapter = tree.root.appendingPathComponent("chapter")
        let old = tree.root.appendingPathComponent("chapter-old")
        let replacement = tree.root.appendingPathComponent("replacement")
        var hooks = ChildDirectoryOpenHooks()
        hooks.beforeOpen = {
            _ = rename(chapter.path, old.path)
            _ = rename(replacement.path, chapter.path)
        }

        #expect(throws: ResourceReadError.changedRoot) {
            try root.childDirectory(ResourceTestSupport.reference("chapter"), hooks: hooks)
        }
        #expect(try String(contentsOf: chapter.appendingPathComponent("image.txt"), encoding: .utf8) ==
            "REPLACEMENT", "the replacement was present for the actual constrained open")
    }

    @Test func anAncestorSymlinkToTheSameChildIsRefusedAtTheRealOpen() throws {
        let tree = try ResourceTestSupport.makeTree()
        defer { tree.cleanup() }
        try tree.write("ORIGINAL", to: "parent/chapter/image.txt")
        let root = try DirectoryLease(opening: tree.root)
        defer { root.close() }
        let parent = tree.root.appendingPathComponent("parent")
        let parked = tree.root.appendingPathComponent("parked")
        var hooks = ChildDirectoryOpenHooks()
        hooks.beforeOpen = {
            _ = rename(parent.path, parked.path)
            _ = symlink("parked", parent.path)
        }

        // The final chapter inode remains exactly the expected object. Without O_NOFOLLOW_ANY the identity and
        // changed-name checks would both accept this substituted ancestor, so this checks the real open flags.
        #expect(throws: ResourceReadError.denied) {
            try root.childDirectory(ResourceTestSupport.reference("parent/chapter"), hooks: hooks)
        }
        #expect(try String(contentsOf: parked.appendingPathComponent("chapter/image.txt"), encoding: .utf8)
            == "ORIGINAL")
    }

    @Test func replacingAnOpenedChildBeforePublicationClosesItsDescriptor() throws {
        let tree = try ResourceTestSupport.makeTree()
        defer { tree.cleanup() }
        try tree.write("ORIGINAL", to: "chapter/image.txt")
        try tree.write("REPLACEMENT", to: "replacement/image.txt")
        let baseline = ResourceTestSupport.openDescriptorCount(under: tree.base)
        let root = try DirectoryLease(opening: tree.root)
        let chapter = tree.root.appendingPathComponent("chapter")
        let parked = tree.root.appendingPathComponent("chapter-old")
        let replacement = tree.root.appendingPathComponent("replacement")
        var hooks = ChildDirectoryOpenHooks()
        hooks.afterOpen = {
            _ = rename(chapter.path, parked.path)
            _ = rename(replacement.path, chapter.path)
        }

        #expect(throws: ResourceReadError.changedRoot) {
            try root.childDirectory(ResourceTestSupport.reference("chapter"), hooks: hooks)
        }
        root.close()
        #expect(ResourceTestSupport.openDescriptorCount(under: tree.base) == baseline)
        #expect(try String(contentsOf: chapter.appendingPathComponent("image.txt"), encoding: .utf8)
            == "REPLACEMENT")
    }

    @Test func aRootReplacementBeforeTheRealOpenCannotPublishAChildLease() throws {
        let tree = try ResourceTestSupport.makeTree()
        defer { tree.cleanup() }
        try tree.write("ORIGINAL", to: "chapter/image.txt")
        try tree.write("REPLACEMENT", to: "new-root/chapter/image.txt")
        let root = try DirectoryLease(opening: tree.root)
        defer { root.close() }
        let oldRoot = tree.base.appendingPathComponent("old-root")
        var hooks = ChildDirectoryOpenHooks()
        hooks.beforeOpen = {
            _ = rename(tree.root.path, oldRoot.path)
            _ = rename(oldRoot.appendingPathComponent("new-root").path, tree.root.path)
        }

        #expect(throws: ResourceReadError.changedRoot) {
            try root.childDirectory(ResourceTestSupport.reference("chapter"), hooks: hooks)
        }
        #expect(try String(contentsOf: tree.root.appendingPathComponent("chapter/image.txt"), encoding: .utf8)
            == "REPLACEMENT")
    }

    @Test func replacingTheChildNameAfterAcquisitionDoesNotRetargetItsReads() throws {
        let tree = try ResourceTestSupport.makeTree()
        defer { tree.cleanup() }
        try tree.write("ORIGINAL", to: "chapter/image.txt")
        try tree.write("REPLACEMENT", to: "replacement/image.txt")
        let root = try DirectoryLease(opening: tree.root)
        defer { root.close() }
        let child = try root.childDirectory(ResourceTestSupport.reference("chapter"))
        defer { child.close() }
        let chapter = tree.root.appendingPathComponent("chapter")
        let old = tree.root.appendingPathComponent("chapter-old")
        try FileManager.default.moveItem(at: chapter, to: old)
        try FileManager.default.moveItem(at: tree.root.appendingPathComponent("replacement"), to: chapter)

        #expect(throws: ResourceReadError.changedRoot) {
            try ContainedResourceReader.read(ResourceTestSupport.reference("image.txt"), in: child, maxBytes: 1024)
        }
    }

    @Test func anAdmittedChildIsIndependentOfTheParentDescriptorClosing() throws {
        let tree = try ResourceTestSupport.makeTree()
        defer { tree.cleanup() }
        try tree.write("inside", to: "chapter/image.txt")
        let baseline = ResourceTestSupport.openDescriptorCount(under: tree.base)
        let root = try DirectoryLease(opening: tree.root)
        var hooks = ChildDirectoryOpenHooks()
        hooks.afterOpen = { root.close() }
        let child = try root.childDirectory(ResourceTestSupport.reference("chapter"), hooks: hooks)

        #expect(try ContainedResourceReader.read(
            ResourceTestSupport.reference("image.txt"), in: child, maxBytes: 1024
        ).bytes == Data("inside".utf8))
        child.close()
        #expect(ResourceTestSupport.openDescriptorCount(under: tree.base) == baseline)
        #expect(throws: ResourceReadError.leaseClosed) {
            try root.childDirectory(ResourceTestSupport.reference("chapter"))
        }
    }

    @Test func aForgedUnparsedComponentCannotBypassTheChildBoundary() throws {
        let tree = try ResourceTestSupport.makeTree()
        defer { tree.cleanup() }
        let root = try DirectoryLease(opening: tree.root)
        defer { root.close() }

        #expect(throws: ResourceReadError.invalidReference) {
            try root.childDirectory(ResourceReference(components: ["..", "outside"]))
        }
        #expect(throws: ResourceReadError.invalidReference) {
            try root.childDirectory(ResourceReference(components: ["chapter/../../outside"]))
        }
    }
}
