import Foundation
@testable import TextFilters

/// Small, real executable shell scripts written to a scratch directory per
/// test — real subprocess launches, not mocked (epic-14-implementation.md
/// §14's note that this evidence is not subject to the no-macOS-runtime
/// caveat that applies to on-device UI journeys).
enum TextFilterFixtures {
    /// A watchdog delay that returns once the fixture has written
    /// `expectedCount` pid lines to `url` (its readiness signal), so the
    /// production timeout verdict and process-group containment run after the
    /// fixture is provably up rather than racing shell startup under load.
    /// `readinessBound` only stops a fixture that never reports from hanging
    /// the test: the timeout then fires anyway and the test's own readiness
    /// check fails it cleanly.
    static func watchdogDelay(
        afterPIDLines expectedCount: Int,
        at url: URL,
        readinessBound: Duration = .seconds(60)
    ) -> TextFilterProcessSession.WatchdogDelay {
        { _ in
            let deadline = ContinuousClock.now.advanced(by: readinessBound)
            while !Task.isCancelled, ContinuousClock.now < deadline {
                let lines = (try? String(contentsOf: url, encoding: .utf8))?
                    .split(separator: "\n").count ?? 0
                if lines >= expectedCount {
                    return
                }
                try? await Task.sleep(for: .milliseconds(10))
            }
        }
    }

    /// True only when `kill(pid, 0)` fails with `ESRCH`. Any other outcome
    /// (success, `EPERM`, or an unexpected errno) means the process is not
    /// established as gone, so a containment test cannot pass on an
    /// indeterminate probe.
    static func processIsGone(_ pid: pid_t) -> Bool {
        kill(pid, 0) == -1 && errno == ESRCH
    }

    /// True when the process is known to exist: `kill(pid, 0)` succeeded, or
    /// failed with `EPERM` (it exists but is not ours to signal).
    static func processExists(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    static func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    static func makeExecutableScript(
        _ contents: String,
        named name: String = "\(UUID().uuidString).sh",
        in directory: URL
    ) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    @discardableResult
    static func makeNonExecutableFile(
        _ contents: String = "not a script",
        named name: String = "\(UUID().uuidString).txt",
        in directory: URL
    ) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        return url
    }

    // MARK: - Named scripts

    static let uppercase = "#!/bin/sh\ncat | tr 'a-z' 'A-Z'\n"
    static let echoStdin = "#!/bin/sh\ncat\n"
    static let exitNonZero = "#!/bin/sh\necho 'something went wrong' >&2\nexit 7\n"
    static let sleepLong = "#!/bin/sh\nsleep 5\n"
    static let invalidUTF8Output = "#!/bin/sh\nprintf '\\377\\376'\n"
    static let printWorkingDirectory = "#!/bin/sh\npwd\n"

    static func oversizedOutput(bytes: Int) -> String {
        "#!/bin/sh\nyes A | head -c \(bytes)\n"
    }

    static let printSelectedEnvironment = """
    #!/bin/sh
    echo "PATH=$PATH"
    echo "DOC=$MACDOWN_DOCUMENT_PATH"
    echo "SEL=$MACDOWN_SELECTION_LENGTH"
    echo "SECRET=$MACDOWN_TEST_SECRET"
    """
}
