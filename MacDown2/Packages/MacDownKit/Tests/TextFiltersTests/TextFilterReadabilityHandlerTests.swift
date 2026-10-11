import Foundation
import Testing
@testable import TextFilters

/// A readability callback that was already queued when the session tore down (or whose FileHandle was closed) used to
/// call `FileHandle.availableData`, which raises an uncatchable `NSFileHandleOperationException` ("Bad file
/// descriptor") and terminates the whole process. Observed as a test-process crash in the full TextFilter run; in the
/// app it would take down every window.
struct TextFilterReadabilityHandlerTests {
    @Test func aCallbackThatRunsAfterTeardownReadsNothingAndDoesNotCrash() throws {
        let session = TextFilterProcessSession(maxOutputBytes: 1024)
        session.installReadabilityHandlers()
        let stdoutHandle = session.stdoutPipe.fileHandleForReading
        let queuedCallback = try #require(stdoutHandle.readabilityHandler)

        session.teardownHandlers()
        try stdoutHandle.close() // the descriptor the old code would have read is now invalid
        queuedCallback(stdoutHandle) // the callback that was already queued fires late
    }

    @Test func aCallbackThatRunsAfterTeardownOnStderrAlsoReadsNothing() throws {
        let session = TextFilterProcessSession(maxOutputBytes: 1024)
        session.installReadabilityHandlers()
        let stderrHandle = session.stderrPipe.fileHandleForReading
        let queuedCallback = try #require(stderrHandle.readabilityHandler)

        session.teardownHandlers()
        try stderrHandle.close()
        queuedCallback(stderrHandle)
    }

    @Test func dataWrittenBeforeTeardownIsStillDeliveredThroughTheOwnedDescriptor() throws {
        let session = TextFilterProcessSession(maxOutputBytes: 1024)
        session.installReadabilityHandlers()
        let handle = session.stdoutPipe.fileHandleForReading
        let callback = try #require(handle.readabilityHandler)
        try session.stdoutPipe.fileHandleForWriting.write(contentsOf: Data("hello".utf8))

        callback(handle) // reads through the duplicated descriptor, not availableData

        session.teardownHandlers()
    }
}
