import Darwin
import Foundation
import Testing
@testable import TextFilters

/// Regressions from the fourth independent merge-gate pass over E14B.
@Suite("TextFilter fourth-pass regressions")
struct TextFilterFourthPassRegressionTests {
    private static func command(
        _ script: String,
        named name: String = "\(UUID().uuidString).sh",
        in directory: URL
    ) throws -> TextFilterCommand {
        let url = try TextFilterFixtures.makeExecutableScript(script, named: name, in: directory)
        return TextFilterCommand(id: name, name: name, executableURL: url)
    }

    /// The previous implementation appended the over-cap chunk, released
    /// the buffer lock, and only then requested `.oversized`; a clean exit
    /// plus both EOFs could commit `.exited(0)` in that gap. Repeating the
    /// one-byte-over boundary exercises the exact scheduler-sensitive edge
    /// while `TextFilterTerminalStateTests` proves the ordering without a
    /// subprocess.
    @Test func oneByteOverTheOutputCapNeverWinsTheExitRace() async throws {
        let directory = try TextFilterFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cap = 4096
        let command = try Self.command(TextFilterFixtures.oversizedOutput(bytes: cap + 1), in: directory)
        let runner = TextFilterRunner(limits: .init(timeout: .seconds(5), maxOutputBytes: cap))

        for _ in 0 ..< 32 {
            do {
                _ = try await runner.run(command, input: "")
                Issue.record("one byte over the output cap must never be accepted as a successful transform")
            } catch TextFilterError.outputTooLarge {
                // expected
            }
        }
    }

    /// Membership inspection is part of the completion proof. A failed
    /// process-table query must therefore surface `terminationUnconfirmed`,
    /// never be collapsed to "no live members" and allow success.
    @Test func unconfirmedGroupMembershipFailsClosedInsteadOfReturningSuccess() async throws {
        let directory = try TextFilterFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let command = try Self.command("#!/bin/sh\nprintf ok\n", in: directory)
        let context = TextFilterLaunchContext(documentURL: nil, selectionLength: 0)
        let session = TextFilterProcessSession(
            maxOutputBytes: 4096,
            membershipStateOverride: { .unconfirmed }
        )

        do {
            _ = try await session.run(command: command, input: "", context: context, timeout: .seconds(5))
            Issue.record("unconfirmed process-group membership must never permit a successful transform")
        } catch TextFilterError.terminationUnconfirmed {
            // expected
        }
    }

    /// `F_SETNOSIGPIPE` protects MacDown's own stdin writer, so failure to
    /// install it is a launch-boundary failure, not a best-effort tweak.
    /// Closing the write descriptor gives us a real deterministic `EBADF`
    /// path without mocking libc.
    @Test func failedNoSigpipeSetupIsCheckedBeforeAnyChildLaunch() {
        let group = TextFilterProcessGroup()
        let stdin = Pipe()
        let pipes = TextFilterProcessGroup.StandardStreamPipes(stdin: stdin, stdout: Pipe(), stderr: Pipe())
        close(stdin.fileHandleForWriting.fileDescriptor)

        #expect(throws: TextFilterProcessGroup.SpawnError.self) {
            try group.configureParentStdinWriteDescriptor(pipes)
        }
        #expect(group.pid == nil)
    }
}
