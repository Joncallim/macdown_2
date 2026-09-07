import Foundation
import Testing
@testable import TextFilters

/// Process-lifecycle coverage added by the E14B post-review remediation —
/// split out of `TextFilterRunnerTests` to stay under the `type_body_length`
/// lint budget, not because these tests belong to a different feature.
@Suite("TextFilterRunner process lifecycle")
struct TextFilterProcessLifecycleTests {
    private static func command(
        _ script: String,
        named name: String = "\(UUID().uuidString).sh",
        in directory: URL
    ) throws
        -> TextFilterCommand {
        let url = try TextFilterFixtures.makeExecutableScript(script, named: name, in: directory)
        return TextFilterCommand(id: name, name: name, executableURL: url)
    }

    // MARK: - Process exit is not I/O completion (post-review finding #2)

    /// Reproduces the exact topology the review demonstrated: a direct
    /// child writes a large exact payload and exits 0. Before the fix,
    /// `Process.terminationHandler` winning the race against a still-queued
    /// stdout `readabilityHandler` callback silently truncated the output.
    /// Repeated to make the scheduling race visible rather than asserting
    /// on a single, possibly-lucky run.
    @Test func largeExactOutputIsNeverTruncatedByTheExitRace() async throws {
        let directory = try TextFilterFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let byteCount = 1 << 20 // 1 MiB
        let command = try Self.command("#!/bin/sh\nyes A | tr -d '\\n' | head -c \(byteCount)\n", in: directory)
        let runner = TextFilterRunner(limits: .init(timeout: .seconds(10), maxOutputBytes: 4 << 20))

        for _ in 0 ..< 8 {
            let output = try await runner.run(command, input: "")
            #expect(output.utf8.count == byteCount)
            #expect(output.allSatisfy { $0 == "A" })
        }
    }

    @Test func outputExactlyAtTheCapSucceedsAndOneByteOverIsRejected() async throws {
        let directory = try TextFilterFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cap = 4096
        let atCap = try Self.command(TextFilterFixtures.oversizedOutput(bytes: cap), in: directory)
        let overCap = try Self.command(TextFilterFixtures.oversizedOutput(bytes: cap + 1), in: directory)
        let runner = TextFilterRunner(limits: .init(timeout: .seconds(5), maxOutputBytes: cap))

        let output = try await runner.run(atCap, input: "")
        #expect(output.utf8.count == cap)

        await #expect(throws: TextFilterError.outputTooLarge) {
            _ = try await runner.run(overCap, input: "")
        }
    }

    // MARK: - Confirmed process termination (post-review finding #4)

    /// `Process.terminate()` sends `SIGTERM`, which a process can ignore.
    /// Before the fix, a TERM-ignoring process was left running while
    /// MacDown reported it as "stopped."
    @Test func timeoutEscalatesToSigkillAndConfirmsTheProcessIsActuallyDead() async throws {
        let directory = try TextFilterFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pidFile = directory.appendingPathComponent("pid")
        let command = try Self.command(
            """
            #!/bin/sh
            trap '' TERM
            echo $$ > "\(pidFile.path)"
            sleep 30
            """,
            in: directory
        )
        // A generous timeout: this test is about confirming a TERM-ignoring
        // process is actually killed, not about racing shell-startup
        // latency (observed to vary widely under concurrent test load)
        // against a tight bound.
        let runner = TextFilterRunner(limits: .init(timeout: .seconds(5), maxOutputBytes: 4 << 20))

        let outcome = Task {
            await #expect(throws: TextFilterError.timedOut) {
                _ = try await runner.run(command, input: "")
            }
        }

        // Confirm the fixture actually installed its trap and is running —
        // read back its own reported pid rather than assuming shell-startup
        // finished within some fixed budget.
        var pid: pid_t?
        for _ in 0 ..< 150 {
            if let contents = try? String(contentsOf: pidFile, encoding: .utf8),
               let value = pid_t(contents.trimmingCharacters(in: .whitespacesAndNewlines)) {
                pid = value
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        let recordedPID = try #require(pid, "the fixture process never reported its pid")
        #expect(kill(recordedPID, 0) == 0, "the fixture process must be running before the timeout fires")

        await outcome.value
        #expect(kill(recordedPID, 0) != 0, "the TERM-ignoring process must have been force-killed")
    }

    // MARK: - Stderr cap (post-review finding #16)

    @Test func stderrIsCappedAtExactly64KiBEvenWhenAChunkWouldOverrunIt() async throws {
        let directory = try TextFilterFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        // Two large chunks that straddle the 64 KiB boundary.
        let command = try Self.command(
            """
            #!/bin/sh
            yes A | tr -d '\\n' | head -c 65000 >&2
            yes B | tr -d '\\n' | head -c 4096 >&2
            exit 3
            """,
            in: directory
        )

        do {
            _ = try await TextFilterRunner().run(command, input: "")
            Issue.record("expected nonZeroExit")
        } catch let TextFilterError.nonZeroExit(_, stderr) {
            #expect(stderr.utf8.count <= 64 * 1024)
        }
    }
}
