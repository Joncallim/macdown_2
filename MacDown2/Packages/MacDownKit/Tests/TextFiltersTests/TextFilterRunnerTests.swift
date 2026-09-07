import Foundation
import Testing
@testable import TextFilters

@Suite("TextFilterRunner")
struct TextFilterRunnerTests {
    private static func command(
        _ script: String,
        named name: String = "\(UUID().uuidString).sh",
        in directory: URL
    ) throws
        -> TextFilterCommand {
        let url = try TextFilterFixtures.makeExecutableScript(script, named: name, in: directory)
        return TextFilterCommand(id: name, name: name, executableURL: url)
    }

    // MARK: - Happy path (J4: end-to-end uppercase)

    @Test func uppercasesInputEndToEnd() async throws {
        let directory = try TextFilterFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let command = try Self.command(TextFilterFixtures.uppercase, in: directory)

        let output = try await TextFilterRunner().run(command, input: "hello world")

        #expect(output == "HELLO WORLD")
    }

    @Test func emptyStdoutOnZeroExitIsASuccessfulEmptyReplacement() async throws {
        let directory = try TextFilterFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let command = try Self.command("#!/bin/sh\ntrue\n", in: directory)

        let output = try await TextFilterRunner().run(command, input: "anything")

        #expect(output.isEmpty)
    }

    // MARK: - Failure modes preserve the original text (§9)

    @Test func launchFailureForANonExecutableFile() async throws {
        let directory = try TextFilterFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try TextFilterFixtures.makeNonExecutableFile(in: directory)
        let command = TextFilterCommand(id: "notes.txt", name: "notes", executableURL: url)

        await #expect(throws: TextFilterError.self) {
            _ = try await TextFilterRunner().run(command, input: "x")
        }
    }

    @Test func launchFailureForAMissingFile() async throws {
        let directory = try TextFilterFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let command = TextFilterCommand(
            id: "gone.sh", name: "gone", executableURL: directory.appendingPathComponent("gone.sh")
        )

        do {
            _ = try await TextFilterRunner().run(command, input: "x")
            Issue.record("expected launchFailed")
        } catch TextFilterError.launchFailed {
            // expected
        }
    }

    @Test func nonZeroExitCarriesTheExitCodeAndStderr() async throws {
        let directory = try TextFilterFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let command = try Self.command(TextFilterFixtures.exitNonZero, in: directory)

        do {
            _ = try await TextFilterRunner().run(command, input: "x")
            Issue.record("expected nonZeroExit")
        } catch let TextFilterError.nonZeroExit(code, stderr) {
            #expect(code == 7)
            #expect(stderr.contains("something went wrong"))
        }
    }

    @Test func timeoutTerminatesTheProcessAndThrowsTimedOut() async throws {
        let directory = try TextFilterFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let command = try Self.command(TextFilterFixtures.sleepLong, in: directory)
        let runner = TextFilterRunner(limits: .init(timeout: .milliseconds(200), maxOutputBytes: 4 << 20))

        let start = ContinuousClock.now
        do {
            _ = try await runner.run(command, input: "")
            Issue.record("expected timedOut")
        } catch TextFilterError.timedOut {
            // expected
        }
        // Terminated near the 200ms bound, not left to run the full 5s sleep.
        #expect(start.duration(to: .now) < .seconds(3))
    }

    @Test func cancellationTerminatesTheProcessAndThrowsCancelled() async throws {
        let directory = try TextFilterFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let command = try Self.command(TextFilterFixtures.sleepLong, in: directory)

        let task = Task {
            try await TextFilterRunner().run(command, input: "")
        }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("expected cancelled")
        } catch TextFilterError.cancelled {
            // expected
        }
    }

    @Test func oversizedStdoutIsRejectedWithoutBufferingItAll() async throws {
        let directory = try TextFilterFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let command = try Self.command(TextFilterFixtures.oversizedOutput(bytes: 50_000_000), in: directory)
        let runner = TextFilterRunner(limits: .init(timeout: .seconds(10), maxOutputBytes: 1024))

        do {
            _ = try await runner.run(command, input: "")
            Issue.record("expected outputTooLarge")
        } catch TextFilterError.outputTooLarge {
            // expected
        }
    }

    @Test func invalidUTF8OutputThrowsOutputNotDecodable() async throws {
        let directory = try TextFilterFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let command = try Self.command(TextFilterFixtures.invalidUTF8Output, in: directory)

        await #expect(throws: TextFilterError.outputNotDecodable) {
            _ = try await TextFilterRunner().run(command, input: "")
        }
    }

    // MARK: - Security/trust boundary (§10)

    @Test func noShellInterpolationOfStdinContent() async throws {
        let directory = try TextFilterFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let command = try Self.command(TextFilterFixtures.echoStdin, in: directory)
        let maliciousLookingInput = "before `touch /tmp/pwned` $(echo pwned) ; echo after"

        let output = try await TextFilterRunner().run(command, input: maliciousLookingInput)

        // The metacharacters travel through as inert stdin bytes — never
        // interpreted, because they never reach a shell command line.
        #expect(output == maliciousLookingInput)
    }

    @Test func environmentExposesOnlyTheDocumentedVariables() async throws {
        let directory = try TextFilterFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let command = try Self.command(TextFilterFixtures.printSelectedEnvironment, in: directory)
        setenv("MACDOWN_TEST_SECRET", "leaked", 1)
        defer { unsetenv("MACDOWN_TEST_SECRET") }

        let documentURL = directory.appendingPathComponent("doc.md")
        let output = try await TextFilterRunner().run(command, input: "hi", documentURL: documentURL)

        #expect(output.contains("PATH=/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin"))
        #expect(output.contains("DOC=\(documentURL.path)"))
        #expect(output.contains("SEL=2"))
        #expect(output.contains("SECRET=\n") || output.hasSuffix("SECRET="))
    }

    @Test func workingDirectoryIsTheDocumentsContainingFolder() async throws {
        let directory = try TextFilterFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let command = try Self.command(TextFilterFixtures.printWorkingDirectory, in: directory)
        let documentURL = directory.appendingPathComponent("doc.md")

        let output = try await TextFilterRunner().run(command, input: "", documentURL: documentURL)

        let resolvedDirectory = URL(fileURLWithPath: directory.path).resolvingSymlinksInPath().path
        let resolvedOutput = URL(fileURLWithPath: output.trimmingCharacters(in: .whitespacesAndNewlines))
            .resolvingSymlinksInPath().path
        #expect(resolvedOutput == resolvedDirectory)
    }

    // MARK: - Adversarial corpus (§15)

    @Test func doesNotWaitOnAForkedGrandchildProcess() async throws {
        let directory = try TextFilterFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let command = try Self.command(TextFilterFixtures.forksAndExitsImmediately, in: directory)

        let start = ContinuousClock.now
        let output = try await TextFilterRunner().run(command, input: "")

        #expect(output.trimmingCharacters(in: .whitespacesAndNewlines) == "done")
        // The direct child exits immediately; only it governs completion.
        #expect(start.duration(to: .now) < .seconds(3))
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

    // MARK: - Cannot block the main actor (§8)

    @Test @MainActor
    func runningATextFilterDoesNotBlockConcurrentMainActorWork() async throws {
        let directory = try TextFilterFixtures.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let command = try Self.command("#!/bin/sh\nsleep 0.3\necho done\n", in: directory)

        var tickCount = 0
        async let filterOutput: String = TextFilterRunner().run(command, input: "")
        async let ticking: Void = {
            for _ in 0 ..< 20 {
                try? await Task.sleep(for: .milliseconds(20))
                tickCount += 1
            }
        }()

        let (output, _) = try await (filterOutput, ticking)
        #expect(output.trimmingCharacters(in: .whitespacesAndNewlines) == "done")
        // If awaiting the filter blocked the main actor, the ticking loop
        // (also main-actor-bound here) could not have made this much
        // progress while the 300ms script ran.
        #expect(tickCount >= 10)
    }
}
