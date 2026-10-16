import Darwin
import Foundation
import Testing
@testable import TextFilters

@Suite("TextFilter detached process ownership")
struct TextFilterRunnerDetachedOwnershipTests {
    private enum FixtureFailure: Error {
        case expected
    }

    private static let supervisorScript = """
    #!/usr/bin/perl
    use POSIX qw(setsid WNOHANG);
    use Time::HiRes qw(time sleep);
    my $supervisor = $$;
    my $pid = fork();
    die "fork failed" unless defined $pid;
    if ($pid == 0) {
        my $sid = setsid();
        die "setsid failed" if $sid == -1;
        $| = 1;
                $SIG{ALRM} = sub { exit 0 };
                alarm 5;
        print "ready $$ $sid\\n";
        while (1) {
            sleep 1;
            exit 0 if getppid() != $supervisor;
        }
    }
    my $shutdown = 0;
    $SIG{TERM} = sub {
        $shutdown = 1;
    };

    sub shutdown_owned_child {
        # Ignore further supervisor TERM delivery while this sequence
        # observes/reaps the direct child. The child cannot be
        # reaped by another process, so a kill is issued only after a
        # WNOHANG wait proves that the pid is still our live child.
        local $SIG{TERM} = 'IGNORE';
        my $waited = waitpid($pid, WNOHANG);
        return if $waited == $pid || $waited == -1;
        return unless $waited == 0;

        kill 'TERM', $pid;
        my $deadline = time + 1;
        while (time < $deadline) {
            $waited = waitpid($pid, WNOHANG);
            return if $waited == $pid || $waited == -1;
            sleep 0.01;
        }
        return if waitpid($pid, WNOHANG) != 0;
        kill 'KILL', $pid;
        waitpid($pid, 0);
    }

    while (1) {
        my $waited = waitpid($pid, WNOHANG);
        last if $waited == $pid;
        if ($shutdown) {
            shutdown_owned_child();
            last;
        }
        sleep 0.01;
    }
    """

    private static func makeSupervisorScript(in directory: URL) throws -> URL {
        try TextFilterFixtures.makeExecutableScript(
            supervisorScript,
            named: "detached-owned-child.pl",
            in: directory
        )
    }

    private static func readWorkerHandoff(
        from handle: FileHandle,
        timeout: Duration = .seconds(2)
    ) async throws -> (pid_t, pid_t) {
        let descriptor = handle.fileDescriptor
        let originalFlags = fcntl(descriptor, F_GETFL)
        guard originalFlags >= 0,
              fcntl(descriptor, F_SETFL, originalFlags | O_NONBLOCK) == 0
        else { throw FixtureFailure.expected }
        defer { _ = fcntl(descriptor, F_SETFL, originalFlags) }

        var bytes: [UInt8] = []
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            try Task.checkCancellation()
            var chunk = [UInt8](repeating: 0, count: 128)
            let count = chunk.withUnsafeMutableBytes { buffer in
                Darwin.read(descriptor, buffer.baseAddress, buffer.count)
            }
            if count > 0 {
                bytes.append(contentsOf: chunk.prefix(Int(count)))
                if bytes.last == 10 {
                    guard let output = String(bytes: bytes, encoding: .utf8) else {
                        throw FixtureFailure.expected
                    }
                    let fields = output.split(whereSeparator: \.isWhitespace)
                    guard fields.count == 3,
                          fields[0] == "ready",
                          let pid = pid_t(fields[1]),
                          let sessionID = pid_t(fields[2]),
                          pid > 0,
                          pid == sessionID
                    else { throw FixtureFailure.expected }
                    return (pid, sessionID)
                }
            } else if count == 0 {
                throw FixtureFailure.expected
            } else if errno != EAGAIN, errno != EWOULDBLOCK, errno != EINTR {
                throw FixtureFailure.expected
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw FixtureFailure.expected
    }

    @Test func detachedOwnedChildIsKilledWhenScopeErrorsAfterHandoff() async throws {
        var recordedPID: pid_t?

        await #expect(throws: FixtureFailure.expected) {
            try await TextFilterFixtures.withOwnedTemporaryDirectory { directory, owner in
                let group = TextFilterProcessGroup()
                let pipes = TextFilterProcessGroup.StandardStreamPipes(
                    stdin: Pipe(),
                    stdout: Pipe(),
                    stderr: Pipe()
                )
                let script = try Self.makeSupervisorScript(in: directory)
                try group.spawn(
                    executableURL: script,
                    workingDirectoryURL: directory,
                    environment: [:],
                    pipes: pipes
                )
                let lease = TextFilterFixtures.makeOwnedProcessLease(
                    cancelSupervisor: { _ = group.terminateGroup(SIGTERM) }
                )
                try await TextFilterFixtures.registerOwnedProcessCleanup(lease: lease, with: owner)
                try await TextFilterFixtures.registerSupervisorFallbackCleanup(
                    group,
                    with: owner,
                    grace: .seconds(1)
                )
                let (readyPID, sessionID) = try await Self.readWorkerHandoff(
                    from: pipes.stdout.fileHandleForReading
                )
                let pid = try #require(group.pid)
                #expect(readyPID != pid)
                #expect(sessionID == readyPID)
                let identity = try #require(TextFilterFixtures.ownedProcessIdentity(for: readyPID))
                let handoff = FixtureProcessHandoff(identity: identity, ownerPID: pid)
                #expect(TextFilterFixtures.processParentPID(readyPID) == pid)
                #expect(TextFilterFixtures.processGroupID(readyPID) == readyPID)
                #expect(lease.adopt(handoff))
                recordedPID = readyPID
                #expect(TextFilterFixtures.processExists(readyPID))

                // The direct child has already called setsid(), so the worker
                // is no longer reachable through the original process group.
                // The supervisor retains child ownership and performs the
                // worker teardown on TERM; the start-identity handoff only
                // proves that the intended child was adopted for observation.
                throw FixtureFailure.expected
            }
        }

        let pid = try #require(recordedPID)
        #expect(
            TextFilterFixtures.processIsGone(pid),
            "an owned detached descendant must be gone after scope cleanup"
        )
    }
}
