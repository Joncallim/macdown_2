import Darwin
import Foundation
@testable import LocalResourceAccess
import Testing

/// Second independent review (authority scope): schedules that would still pass with a protection removed.
extension ContainedResourceReaderTests {
    @Test func theKernelItselfRefusesARawParentTraversalWithoutTheHint() throws {
        let tree = try ResourceTestSupport.makeTree()
        defer { tree.cleanup() }
        let lease = try DirectoryLease(opening: tree.root)

        // Bypasses the realpath hint (which never produces `..`): only O_RESOLVE_BENEATH stands between this and the
        // sentinel.
        #expect(throws: ResourceReadError.denied) {
            try ContainedResourceReader.readStrict(
                relativePath: "../outside/secret.txt", name: "secret.txt", in: lease,
                limits: (1024, ResourceCancellation()), hooks: .none
            )
        }
    }

    @Test func theKernelItselfRefusesAnInRootSymlinkWithoutTheHint() throws {
        let tree = try ResourceTestSupport.makeTree()
        defer { tree.cleanup() }
        try tree.write("real", to: "real.txt")
        try FileManager.default.createSymbolicLink(
            atPath: tree.root.appendingPathComponent("alias.txt").path, withDestinationPath: "real.txt"
        )
        let lease = try DirectoryLease(opening: tree.root)

        #expect(throws: ResourceReadError.denied) {
            try ContainedResourceReader.readStrict(
                relativePath: "alias.txt", name: "alias.txt", in: lease,
                limits: (1024, ResourceCancellation()), hooks: .none
            )
        }
    }

    @Test func anOversizedFileIsRejectedBeforeAnyChunkIsRead() throws {
        let tree = try ResourceTestSupport.makeTree()
        defer { tree.cleanup() }
        try tree.write(String(repeating: "x", count: 5000), to: "big.txt")
        let lease = try DirectoryLease(opening: tree.root)
        let reads = ChunkCounter()
        var hooks = ResourceReadHooks()
        hooks.beforeChunk = { _ in reads.increment() }

        #expect(throws: ResourceReadError.oversized) {
            try ContainedResourceReader.read(
                ResourceTestSupport.reference("big.txt"), in: lease, maxBytes: 1000,
                cancellation: ResourceCancellation(), hooks: hooks
            )
        }
        #expect(reads.value == 0, "the size pre-check must reject before allocating or reading anything")
    }

    @Test func aFIFOIsRejectedPromptlyAndNeverHangsTheReader() throws {
        let tree = try ResourceTestSupport.makeTree()
        defer { tree.cleanup() }
        #expect(mkfifo(tree.root.appendingPathComponent("pipe").path, 0o600) == 0)
        let lease = try DirectoryLease(opening: tree.root)
        let outcome = ChunkCounter()
        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            if (try? ContainedResourceReader.read(ResourceTestSupport.reference("pipe"), in: lease, maxBytes: 1024)) ==
                nil {
                outcome.increment()
            }
            finished.signal()
        }

        // Bounded so a regression (blocking open) FAILS instead of hanging the whole run.
        #expect(finished.wait(timeout: .now() + 30) == .success, "a FIFO must not block the reader")
        #expect(outcome.value == 1)
    }

    @Test func theRuntimeEnforcementCheckPassesOnThisKernel() throws {
        try ContainedResourceReader.verifyEnforcement()
    }
}

final class ChunkCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() {
        lock.lock()
        count += 1
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}
