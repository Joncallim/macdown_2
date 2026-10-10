import Darwin
import Foundation
@testable import LocalResourceAccess
import Testing

/// Independent-review follow-ups for stage A: schedules the first test set did not discriminate.
extension ContainedResourceReaderTests {
    private final class Box: @unchecked Sendable {
        var before = 0
        var after = 0
    }

    @Test func aFileTruncatedMidReadIsChangedDuringRead() throws {
        let tree = try ResourceTestSupport.makeTree()
        defer { tree.cleanup() }
        try tree.write(String(repeating: "x", count: 200_000), to: "t.txt")
        let lease = try DirectoryLease(opening: tree.root)
        let url = tree.root.appendingPathComponent("t.txt")
        var hooks = ResourceReadHooks()
        hooks.beforeChunk = { done in
            if done > 0 {
                truncate(url.path, 100_000)
            }
        }

        #expect(throws: ResourceReadError.changedDuringRead) {
            try ContainedResourceReader.read(
                ResourceTestSupport.reference("t.txt"), in: lease, maxBytes: 1 << 20,
                cancellation: ResourceCancellation(), hooks: hooks
            )
        }
    }

    @Test func aFileThatGrowsSlightlyButStaysUnderTheCapIsChangedDuringRead() throws {
        let tree = try ResourceTestSupport.makeTree()
        defer { tree.cleanup() }
        try tree.write(String(repeating: "x", count: 200_000), to: "g.txt")
        let lease = try DirectoryLease(opening: tree.root)
        let url = tree.root.appendingPathComponent("g.txt")
        var hooks = ResourceReadHooks()
        hooks.beforeChunk = { done in
            guard done == 65536, let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data("0123456789".utf8))
        }

        #expect(throws: ResourceReadError.changedDuringRead) {
            try ContainedResourceReader.read(
                ResourceTestSupport.reference("g.txt"), in: lease, maxBytes: 1 << 20,
                cancellation: ResourceCancellation(), hooks: hooks
            )
        }
    }

    @Test func aFileGrowingToExactlyOneByteOverTheCapIsOversized() throws {
        let tree = try ResourceTestSupport.makeTree()
        defer { tree.cleanup() }
        try tree.write(String(repeating: "x", count: 1000), to: "e.txt")
        let lease = try DirectoryLease(opening: tree.root)
        let url = tree.root.appendingPathComponent("e.txt")
        var hooks = ResourceReadHooks()
        hooks.beforeChunk = { done in
            guard done == 0, let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data("y".utf8)) // 1001 bytes against a cap of 1000
        }

        #expect(throws: ResourceReadError.oversized) {
            try ContainedResourceReader.read(
                ResourceTestSupport.reference("e.txt"), in: lease, maxBytes: 1000,
                cancellation: ResourceCancellation(), hooks: hooks
            )
        }
    }

    @Test func aMaximumCapDoesNotTrap() throws {
        let tree = try ResourceTestSupport.makeTree()
        defer { tree.cleanup() }
        try tree.write("small", to: "s.txt")
        let lease = try DirectoryLease(opening: tree.root)

        let snapshot = try ContainedResourceReader.read(
            ResourceTestSupport.reference("s.txt"), in: lease, maxBytes: Int.max
        )
        #expect(snapshot.bytes == Data("small".utf8))
    }

    @Test func aLeafSwappedForAnInRootSymlinkBetweenTheHintAndTheOpenIsDenied() throws {
        let tree = try ResourceTestSupport.makeTree()
        defer { tree.cleanup() }
        try tree.write("original", to: "a.txt")
        try tree.write("other-in-root", to: "b.txt")
        let lease = try DirectoryLease(opening: tree.root)
        let leaf = tree.root.appendingPathComponent("a.txt")
        var hooks = ResourceReadHooks()
        hooks.beforeOpen = {
            try? FileManager.default.removeItem(at: leaf)
            try? FileManager.default.createSymbolicLink(atPath: leaf.path, withDestinationPath: "b.txt")
        }

        #expect(throws: ResourceReadError.denied) {
            try ContainedResourceReader.read(
                ResourceTestSupport.reference("a.txt"), in: lease, maxBytes: 1024,
                cancellation: ResourceCancellation(), hooks: hooks
            )
        }
    }

    @Test func closingTheLeaseInsideTheReadKeepsTheDirectoryDescriptorOpenUntilTheReadReturns() throws {
        let tree = try ResourceTestSupport.makeTree()
        defer { tree.cleanup() }
        try tree.write("data", to: "d.txt")
        let baseline = ResourceTestSupport.openFileDescriptorCount()
        let lease = try DirectoryLease(opening: tree.root)
        let box = Box()
        var hooks = ResourceReadHooks()
        hooks.afterOpen = { // runs inside the root descriptor's use
            box.before = ResourceTestSupport.openFileDescriptorCount()
            lease.close()
            box.after = ResourceTestSupport.openFileDescriptorCount()
        }

        let snapshot = try ContainedResourceReader.read(
            ResourceTestSupport.reference("d.txt"), in: lease, maxBytes: 1024,
            cancellation: ResourceCancellation(), hooks: hooks
        )

        #expect(snapshot.bytes == Data("data".utf8))
        #expect(box.after == box.before, "close() while the root descriptor is in use must not close it")
        #expect(ResourceTestSupport.openFileDescriptorCount() <= baseline, "and it closes once the read returns")
    }

    @Test func closingAFileLeaseMidReadDoesNotCloseTheDescriptorBeingRead() throws {
        let tree = try ResourceTestSupport.makeTree()
        defer { tree.cleanup() }
        let body = String(repeating: "z", count: 200_000)
        try tree.write(body, to: "f.txt")
        let baseline = ResourceTestSupport.openFileDescriptorCount()
        let lease = try FileLease(opening: tree.root.appendingPathComponent("f.txt"))
        var hooks = ResourceReadHooks()
        hooks.beforeChunk = { done in
            if done > 0 {
                lease.close()
            }
        }

        let snapshot = try ContainedResourceReader.read(
            lease, maxBytes: 1 << 20, cancellation: ResourceCancellation(), hooks: hooks
        )

        #expect(snapshot.bytes.count == body.utf8.count)
        #expect(ResourceTestSupport.openFileDescriptorCount() <= baseline)
        #expect(throws: ResourceReadError.leaseClosed) { try ContainedResourceReader.read(lease, maxBytes: 1024) }
    }

    @Test func aDirectoryNameSwappedForASymlinkBetweenResolutionAndOpenIsNotPinned() throws {
        // A lease for a path that is itself a symlink resolves it once; the open then refuses symlinks. Here the
        // canonical path is real, so the lease opens; swapping it for a symlink afterwards is `changedRoot`.
        let tree = try ResourceTestSupport.makeTree()
        defer { tree.cleanup() }
        try tree.write("x", to: "x.txt")
        let lease = try DirectoryLease(opening: tree.root)
        let moved = tree.base.appendingPathComponent("moved")
        try FileManager.default.moveItem(at: tree.root, to: moved)
        try FileManager.default.createSymbolicLink(at: tree.root, withDestinationURL: moved)

        #expect(throws: ResourceReadError.changedRoot) {
            try ContainedResourceReader.read(ResourceTestSupport.reference("x.txt"), in: lease, maxBytes: 1024)
        }
    }

    @Test func aCombiningMarkAfterTheSeparatorIsNotMistakenForOutsideTheRoot() throws {
        let tree = try ResourceTestSupport.makeTree()
        defer { tree.cleanup() }
        let name = "\u{0301}x.txt"
        try tree.write("combining", to: name)
        let lease = try DirectoryLease(opening: tree.root)
        let encoded = "/%CC%81x.txt"

        let snapshot = try ContainedResourceReader.read(
            ResourceTestSupport.reference(encoded),
            in: lease,
            maxBytes: 1024
        )
        #expect(snapshot.bytes == Data("combining".utf8))
    }
}

extension ResourceReferenceTests {
    @Test func aCombiningMarkAfterASeparatorOrQueryMarkDoesNotHideIt() throws {
        #expect(try ResourceReference.parse("/a/\u{0301}b").components == ["a", "\u{0301}b"])
        #expect(try ResourceReference.parse("/a.png?\u{0301}q").components == ["a.png"], "the query still starts at ?")
        #expect(
            try ResourceReference.parse("/a/.\u{0301}/b").components == ["a", ".\u{0301}", "b"],
            "not a dot segment"
        )
    }

    @Test func aNetworkPathReferenceIsRejected() {
        #expect(throws: ResourceReadError.invalidReference) { try ResourceReference.parse("//evil.com/x") }
    }
}
