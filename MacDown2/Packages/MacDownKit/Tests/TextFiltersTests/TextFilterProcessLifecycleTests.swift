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

        _ = await outcome.value
        #expect(kill(recordedPID, 0) != 0, "the TERM-ignoring process must have been force-killed")
    }

    // MARK: - Whole-process-group containment (second-adversarial-pass finding #2)

    /// A timeout must bound the whole filter invocation, not merely the
    /// interpreter MacDown directly launched: an ordinary pipeline's later
    /// stages are descendants, not the direct child.
    ///
    /// Each stage is spawned via `sh -c '...'` rather than a bare `(...)`
    /// subshell so `$$` reports that stage's own *real* forked pid — POSIX
    /// `$$` is fixed at shell-startup and is otherwise simply inherited,
    /// unchanged, across a `(...)` subshell's `fork()`, so a bare `$$`
    /// inside one silently reports the *top-level* shell's pid instead
    /// (the mistake an earlier version of this test made, which is why it
    /// appeared to pass while actually re-checking the already-verified
    /// direct child instead of a real descendant).
    @Test func timeoutContainsEveryProcessInAForegroundPipeline() async throws {
        let directory = try TextFilterFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pidFile = directory.appendingPathComponent("pids")
        let command = try Self.command(
            """
            #!/bin/sh
            sh -c 'echo "a=$$" >> "\(pidFile.path)"; exec sleep 30' | sh -c 'echo "b=$$" >> "\(pidFile.path)"; exec cat'
            """,
            in: directory
        )
        let runner = TextFilterRunner(limits: .init(timeout: .milliseconds(300), maxOutputBytes: 4 << 20))

        await #expect(throws: TextFilterError.timedOut) {
            _ = try await runner.run(command, input: "")
        }

        let pids = try await Self.waitForReportedPIDs(at: pidFile, expectedCount: 2)
        for pid in pids {
            #expect(kill(pid, 0) != 0, "every process the timed-out pipeline spawned must be contained")
        }
    }

    /// Same containment guarantee for explicit `Task` cancellation as for
    /// timeout — cancellation must not leave descendants running either.
    /// `$!` (not `$$` inside the backgrounded subshell) captures the
    /// background job's own real pid — see the doc comment above.
    @Test func cancellationContainsEveryProcessInABackgroundedDescendant() async throws {
        let directory = try TextFilterFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pidFile = directory.appendingPathComponent("pid")
        let command = try Self.command(
            """
            #!/bin/sh
            sleep 30 &
            echo $! > "\(pidFile.path)"
            sleep 30
            """,
            in: directory
        )

        let task = Task {
            try await TextFilterRunner().run(command, input: "")
        }
        let recordedPID = try await Self.waitForReportedPIDs(at: pidFile, expectedCount: 1)[0]
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("expected cancelled")
        } catch TextFilterError.cancelled {
            // expected
        }
        #expect(kill(recordedPID, 0) != 0, "the backgrounded descendant must be contained on cancellation too")
    }

    /// Finding #2 explicitly calls out that TERM-ignoring behavior is not
    /// limited to the direct child — a descendant can ignore it too, and
    /// containment still has to finish the job with `SIGKILL`.
    @Test func termIgnoringDescendantIsEscalatedToSigkill() async throws {
        let directory = try TextFilterFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pidFile = directory.appendingPathComponent("pid")
        let command = try Self.command(
            """
            #!/bin/sh
            sh -c 'trap "" TERM; exec sleep 30' &
            echo $! > "\(pidFile.path)"
            sleep 30
            """,
            in: directory
        )
        let runner = TextFilterRunner(limits: .init(timeout: .milliseconds(300), maxOutputBytes: 4 << 20))

        await #expect(throws: TextFilterError.timedOut) {
            _ = try await runner.run(command, input: "")
        }

        let recordedPID = try await Self.waitForReportedPIDs(at: pidFile, expectedCount: 1)[0]
        #expect(kill(recordedPID, 0) != 0, "a TERM-ignoring descendant must still be force-killed")
    }

    /// The ordinary, non-adversarial case: an ordinary two-stage pipeline
    /// leaves no survivor once it completes normally — containment's
    /// bookkeeping does not accidentally create a leak of its own.
    @Test func ordinaryPipelineLeavesNoSurvivor() async throws {
        let directory = try TextFilterFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pidFile = directory.appendingPathComponent("pids")
        let command = try Self.command(
            """
            #!/bin/sh
            sh -c 'echo "a=$$" >> "\(pidFile.path)"; exec cat' | sh -c 'echo "b=$$" >> "\(pidFile
                .path)"; exec tr "a-z" "A-Z"'
            """,
            in: directory
        )

        let output = try await TextFilterRunner().run(command, input: "hi")
        #expect(output == "HI")

        let pids = try await Self.waitForReportedPIDs(at: pidFile, expectedCount: 2)
        for pid in pids {
            #expect(kill(pid, 0) != 0, "an ordinary completed pipeline must leave no survivor")
        }
    }

    /// Reads however many `label=pid` lines the fixture script has written
    /// so far, polling until at least `expectedCount` are present.
    private static func waitForReportedPIDs(at url: URL, expectedCount: Int) async throws -> [pid_t] {
        for _ in 0 ..< 150 {
            if let contents = try? String(contentsOf: url, encoding: .utf8) {
                let pids = contents
                    .split(separator: "\n")
                    .compactMap { line in line.split(separator: "=").last.flatMap { pid_t($0) } }
                if pids.count >= expectedCount {
                    return pids
                }
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("fixture never reported \(expectedCount) pid(s) at \(url.path)")
        return []
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
