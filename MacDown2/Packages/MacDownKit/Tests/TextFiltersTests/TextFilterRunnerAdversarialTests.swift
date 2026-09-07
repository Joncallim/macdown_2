import Darwin
import Foundation
import Testing
@testable import TextFilters

/// Split out of `TextFilterRunnerTests` (§15's adversarial corpus, plus
/// the second- and third-adversarial-pass process-lifetime regression
/// tests it grew) to stay under the project's file-length budget.
@Suite("TextFilterRunner adversarial corpus")
struct TextFilterRunnerAdversarialTests {
    private static func command(
        _ script: String,
        named name: String = "\(UUID().uuidString).sh",
        in directory: URL
    ) throws
        -> TextFilterCommand {
        let url = try TextFilterFixtures.makeExecutableScript(script, named: name, in: directory)
        return TextFilterCommand(id: name, name: name, executableURL: url)
    }

    /// Second-adversarial-pass finding #2: the direct-child-only policy
    /// this test originally codified ("MacDown never waits on a
    /// backgrounded grandchild") independently caused finding #1's
    /// fake-EOF bug, because the grandchild kept inheriting the pipe open
    /// past the direct child's own exit. The bounded-invocation contract
    /// replaces "never waits on it" with "actively contains it": the
    /// grandchild is confirmed killed, not merely ignored, and MacDown
    /// still returns promptly because containment is bounded, not because
    /// it stopped looking.
    ///
    /// Third-adversarial-pass finding #1: containing this grandchild is
    /// what produces the real stdout EOF here — the direct child's own
    /// "done" was already fully written and read *before* that EOF, but
    /// the forced kill is still what closes the pipe. That must not be
    /// enough to call this run successful; a still-alive grandchild
    /// holding the pipe open past the direct child's exit means this
    /// invocation's own I/O contract was never actually satisfied on its
    /// own, and the corrected ordering (commit fail-closed before
    /// containing, not after) makes that the observed outcome here too.
    ///
    /// Third-adversarial-pass finding #9: the fixture no longer records
    /// the grandchild's pid via `$$` inside a `(...)` subshell — that
    /// value is fixed at the *outer* shell's own startup and is merely
    /// inherited across the subshell's `fork()`, not recomputed, so it
    /// previously reported the already-dead direct child's pid rather
    /// than the grandchild's. A flat `&` background directly in the
    /// top-level script, read back via `$!` (computed dynamically after
    /// the fork), reports the grandchild's own real pid.
    @Test func containsABackgroundedGrandchildRatherThanLettingItSurvive() async throws {
        let directory = try TextFilterFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pidFile = directory.appendingPathComponent("grandchild-pid")
        let command = try Self.command(
            """
            #!/bin/sh
            sleep 30 &
            echo $! > "\(pidFile.path)"
            echo done
            """,
            in: directory
        )

        let start = ContinuousClock.now
        do {
            _ = try await TextFilterRunner().run(command, input: "")
            Issue.record("expected outputIncomplete")
        } catch TextFilterError.outputIncomplete {
            // expected
        }
        // Bounded by containment (drain grace + SIGTERM/SIGKILL grace),
        // not by waiting out the grandchild's own 30s sleep.
        #expect(start.duration(to: .now) < .seconds(3))

        var grandchildPID: pid_t?
        for _ in 0 ..< 100 {
            if let contents = try? String(contentsOf: pidFile, encoding: .utf8),
               let value = pid_t(contents.trimmingCharacters(in: .whitespacesAndNewlines)) {
                grandchildPID = value
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        let recordedPID = try #require(grandchildPID, "the grandchild fixture never reported its pid")
        #expect(kill(recordedPID, 0) != 0, "the backgrounded grandchild must have been contained, not left running")
    }

    /// Third-adversarial-pass finding #7: this session's containment
    /// reaches the invocation's *initial process group* — a real,
    /// non-trivial guarantee (it defeats a plain backgrounded `&` job or
    /// an ordinary pipeline stage that outlives its shell), but not
    /// literally "every descendant, however deeply nested or regrouped."
    /// A descendant that calls `setsid()` to leave the group is outside
    /// E14's containment contract by explicit, documented design — this
    /// makes that boundary executable instead of only a doc comment. (The
    /// still-open pipe from this detached descendant is why the run below
    /// fails closed at all here; that part is incidental to what this
    /// test is actually about.)
    @Test func aDescendantThatDetachesItsOwnSessionSurvivesContainmentByDesign() async throws {
        let directory = try TextFilterFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let pidFile = directory.appendingPathComponent("detached-pid")
        let command = try Self.command(
            """
            #!/bin/sh
            perl -e 'use POSIX qw(setsid); setsid(); sleep 30;' &
            echo $! > "\(pidFile.path)"
            exit 0
            """,
            in: directory
        )

        do {
            _ = try await TextFilterRunner().run(command, input: "")
            Issue.record("expected outputIncomplete: the detached descendant still holds the pipe open")
        } catch TextFilterError.outputIncomplete {
            // expected -- see the doc comment above; not what this test verifies
        }

        var detachedPID: pid_t?
        for _ in 0 ..< 100 {
            if let contents = try? String(contentsOf: pidFile, encoding: .utf8),
               let value = pid_t(contents.trimmingCharacters(in: .whitespacesAndNewlines)) {
                detachedPID = value
                break
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        let recordedPID = try #require(detachedPID, "the detached-descendant fixture never reported its pid")
        #expect(
            kill(recordedPID, 0) == 0,
            "a session-detached descendant is documented as outside this contract -- it must survive"
        )
        // This test intentionally leaves a real process running past
        // containment; clean it up directly rather than leaking it.
        kill(recordedPID, SIGKILL)
    }

    /// Third-adversarial-pass finding #1's exact reproducer: a still-alive
    /// background writer has already produced real, well-formed output
    /// before this session's own forced containment kills it — the read
    /// end sees genuine EOF, but only because MacDown closed it, not
    /// because the writer finished. That must never be exposed as a
    /// successful (truncated) result.
    @Test func aStillWritingBackgroundDescendantNeverLaundersItsPartialOutputIntoSuccess() async throws {
        let directory = try TextFilterFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let command = try Self.command(
            """
            #!/bin/sh
            (
                printf PREFIX
                sleep 2
                printf SUFFIX
            ) &
            exit 0
            """,
            in: directory
        )

        let start = ContinuousClock.now
        do {
            _ = try await TextFilterRunner().run(command, input: "")
            Issue.record("expected outputIncomplete -- must never return the pre-kill \"PREFIX\" as success")
        } catch TextFilterError.outputIncomplete {
            // expected
        }
        // Contained well before the backgrounded writer's own 2s sleep
        // would let it write SUFFIX and exit on its own -- this is what
        // guarantees the kill happened while only "PREFIX" existed.
        #expect(start.duration(to: .now) < .seconds(2))
    }

    /// Third-adversarial-pass finding #8: a script that never reads stdin
    /// used to make MacDown call `signal(SIGPIPE, SIG_IGN)` process-wide
    /// and never restore it, silently changing the disposition every
    /// other part of the app (and every filter run after the first) would
    /// see for the rest of the process's lifetime. Confirms the app's own
    /// disposition is unchanged by a run, including one large enough to
    /// actually hit `EPIPE` on the parent's stdin-write descriptor.
    @Test func runningATextFilterNeverChangesTheAppsOwnSigpipeDisposition() async throws {
        func currentDisposition() -> Int {
            var action = sigaction()
            sigaction(SIGPIPE, nil, &action)
            return unsafeBitCast(action.__sigaction_u.__sa_handler, to: Int.self)
        }

        let before = currentDisposition()
        let directory = try TextFilterFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        // Exits immediately without reading stdin, so writing MacDown's
        // input to it hits a closed pipe -- exactly the case
        // `F_SETNOSIGPIPE` on the parent's own write descriptor exists
        // for.
        let command = try Self.command("#!/bin/sh\nexit 0\n", in: directory)
        _ = try? await TextFilterRunner().run(command, input: String(repeating: "x", count: 1 << 20))

        #expect(currentDisposition() == before)
    }

    @Test func concurrentInvocationsOfTheSameScriptDoNotCorruptEachOthersOutput() async throws {
        let directory = try TextFilterFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let command = try Self.command(TextFilterFixtures.uppercase, in: directory)

        async let first = TextFilterRunner().run(command, input: "first")
        async let second = TextFilterRunner().run(command, input: "second")
        let (firstResult, secondResult) = try await (first, second)

        #expect(firstResult == "FIRST")
        #expect(secondResult == "SECOND")
    }

    @Test func aMixOfExecutableAndNonExecutableEntriesOnlyRunsTheExecutableOne() async throws {
        let directory = try TextFilterFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try TextFilterFixtures.makeNonExecutableFile(named: "readme.txt", in: directory)
        let command = try Self.command(TextFilterFixtures.echoStdin, named: "run.sh", in: directory)

        let discovered = TextFilterCommandDiscovery.discoverCommands(in: directory)
        #expect(discovered.map(\.id) == ["run.sh"])

        let output = try await TextFilterRunner().run(command, input: "ok")
        #expect(output == "ok")
    }
}
