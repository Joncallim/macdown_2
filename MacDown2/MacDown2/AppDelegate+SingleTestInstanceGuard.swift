import Foundation

/// Enforces that at most one `MacDown2Tests`-hosted process runs at a time
/// (EPIC-22/#150). A complete no-op for a normal, non-test launch.
///
/// **Root cause this guards against:** `xcodebuild`'s parallel-clone testing
/// mode launches multiple CONCURRENT instances of this same app binary,
/// all sharing the identical bundle identifier `com.joncallim.MacDown2`
/// (confirmed directly via `lsappinfo` during #150's own investigation).
/// Every `MacDown2Tests` process, whatever isolated fixtures its own tests
/// go on to construct, first boots the REAL `MacDown2App`/`AppDelegate` —
/// unavoidable, since Xcode launches the AUT before injecting the test
/// bundle — and that incidental real launch still touches genuinely
/// process-external, bundle-ID-keyed state (`RecoveryBuffer.shared`,
/// `UserDefaults.standard`'s own `com.joncallim.MacDown2.plist`, Launch
/// Services' own bundle-ID registration). Two concurrent clones' incidental
/// real launches can race on exactly that shared state, independent of how
/// carefully each test's OWN fixtures are isolated (`#150`'s own
/// investigation found the specific failing tests already inject isolated
/// `RecoveryBuffer`/`UserDefaults` suites for their OWN assertions —
/// confirming the collision is NOT in the tests' own fixtures, but in this
/// incidental shared real-launch path every process boots regardless).
///
/// **Why serial-only rather than fully isolating this too:** doing the same
/// per-process-unique-suite trick `-UITesting` below already applies to its
/// OWN launch was evaluated and would only isolate the KNOWN Swift-level
/// state (`RecoveryBuffer`, `UserDefaults`) — it would not address the
/// possibility of an OS/AppKit-level assumption (window-server client
/// tracking, Launch Services activation) that two live processes never
/// legitimately share a bundle identifier outside of this test harness's
/// own artificial parallel-clone mechanism, which a normal macOS user never
/// triggers. Chasing that fully is open-ended, AppKit-internals-dependent
/// investigation disproportionate to what this gate needs: `MacDown2Tests`
/// already runs serially in both CI (`.github/workflows/ci.yml`) and the
/// documented local-verification convention. This guard converts an
/// ACCIDENTALLY reintroduced parallel run from an hours-to-diagnose,
/// stochastic test failure into an immediate, actionable one, making that
/// already-adopted serial-only decision an enforced invariant instead of
/// tribal knowledge recorded only in a CI YAML comment.
enum SingleTestInstanceGuard {
    /// `true` exactly when running inside an Xcode-driven test host —
    /// `XCTestConfigurationFilePath` is set by Xcode for any test run
    /// regardless of which test framework (XCTest or Swift Testing) the
    /// individual tests use, since both are hosted through the same
    /// underlying `.xctest` bundle-injection mechanism.
    static var isRunningUnderXCTest: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// Call once, as early as possible in `AppDelegate.init()`. Acquires an
    /// exclusive advisory lock on a fixed, well-known path; if another
    /// `MacDown2Tests` process already holds it, terminates this process
    /// immediately with a diagnostic explaining why, rather than letting it
    /// proceed into a run that would otherwise produce a confusing,
    /// stochastic failure somewhere else entirely.
    static func enforceSingleInstance() {
        guard isRunningUnderXCTest else { return }
        let lockPath = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("com.joncallim.MacDown2.MacDown2Tests.lock")
        let descriptor = open(lockPath, O_CREAT | O_RDWR, 0o644)
        guard descriptor >= 0 else {
            fatalError(
                "SingleTestInstanceGuard: could not open lock file at \(lockPath): "
                    + String(cString: strerror(errno))
            )
        }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            fatalError("""
            MacDown2Tests appears to already be running in another process \
            (flock on \(lockPath) failed: \(String(cString: strerror(errno)))). \
            This scheme is intentionally serial-only: concurrent test-host clones \
            share the bundle identifier com.joncallim.MacDown2 and race on \
            bundle-ID-keyed shared state that every process's own incidental \
            real app launch touches, regardless of how isolated each test's own \
            fixtures are -- see issue #150. Re-run with -parallel-testing-enabled NO \
            (the CI/local canonical configuration), or ensure no other MacDown2Tests \
            run is already in flight.
            """)
        }
        // Deliberately never closed/unlocked: the OS releases this flock the
        // moment this process exits, exactly when the guard should stop
        // applying -- there is no correct earlier point to release it from.
    }
}
