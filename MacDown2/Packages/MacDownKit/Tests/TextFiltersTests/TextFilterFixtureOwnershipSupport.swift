import Darwin
import Foundation
import Testing
@testable import TextFilters

// Ownership state, process identity and bounded teardown stay in one support
// implementation so every fixture follows the same cleanup contract.
// swiftlint:disable file_length

private struct FixtureCleanupRecord: Sendable {
    let cancel: @Sendable () -> Void
    let join: @Sendable () async -> FixtureCleanupJoinResult
}

enum FixtureCleanupJoinResult: Sendable {
    case completed(String?)
    case unresolved(String)
}

struct FixtureCleanupReport: Sendable {
    let failures: [String]
    let unresolved: [String]
}

private enum TaskJoinResult: Sendable {
    case finished(String?)
    case cancelled
}

private actor TaskJoinGate {
    private var result: TaskJoinResult?
    private var continuation: CheckedContinuation<TaskJoinResult, Never>?

    func wait() async -> TaskJoinResult {
        if let result {
            return result
        }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func complete(_ result: TaskJoinResult) {
        guard self.result == nil else { return }
        self.result = result
        continuation?.resume(returning: result)
        continuation = nil
    }
}

struct FixtureProcessIdentity: Sendable, Equatable {
    let pid: pid_t
    let startSeconds: UInt64
    let startMicroseconds: UInt64
}

struct FixtureProcessHandoff: Sendable, Equatable {
    let identity: FixtureProcessIdentity
    let ownerPID: pid_t
}

struct FixtureProcessProbe: Sendable {
    let identity: @Sendable (pid_t) -> FixtureProcessIdentity?
    let parentPID: @Sendable (pid_t) -> pid_t?
    let processIsGone: @Sendable (pid_t) -> Bool
    let processIsZombie: @Sendable (pid_t) -> Bool

    static let darwin = FixtureProcessProbe(
        identity: { TextFilterFixtures.processIdentity($0) },
        parentPID: { TextFilterFixtures.processParentPID($0) },
        processIsGone: { TextFilterFixtures.processIsGone($0) },
        processIsZombie: { TextFilterFixtures.processIsZombie($0) }
    )
}

private struct LeaseSnapshot {
    let identity: FixtureProcessIdentity?
}

final class FixtureProcessGroupCleanup: @unchecked Sendable {
    private enum State {
        case owned
        case reaping
        case released
        case unresolved(String)
    }

    private let group: TextFilterProcessGroup
    private let leaderIdentity: FixtureProcessIdentity?
    private let processIdentity: @Sendable (pid_t) -> FixtureProcessIdentity?
    private let processIsGone: @Sendable (pid_t) -> Bool
    private let beforeReap: @Sendable () -> Void
    private let afterReap: @Sendable () -> Void
    private let terminate: @Sendable (TextFilterProcessGroup, Int32) -> TextFilterProcessGroup.SignalOutcome
    private let lock = NSLock()
    private var state: State = .owned

    init(
        group: TextFilterProcessGroup,
        processIdentity: @escaping @Sendable (pid_t)
            -> FixtureProcessIdentity? = { TextFilterFixtures.processIdentity($0) },
        processIsGone: @escaping @Sendable (pid_t) -> Bool = { TextFilterFixtures.processIsGone($0) },
        beforeReap: @escaping @Sendable () -> Void = {},
        afterReap: @escaping @Sendable () -> Void = {},
        terminate: @escaping @Sendable (TextFilterProcessGroup, Int32) -> TextFilterProcessGroup.SignalOutcome = {
            $0.terminateGroup($1)
        }
    ) {
        self.group = group
        self.processIdentity = processIdentity
        self.processIsGone = processIsGone
        self.beforeReap = beforeReap
        self.afterReap = afterReap
        self.terminate = terminate
        leaderIdentity = group.pid.flatMap(processIdentity)
    }

    /// Disarms signalling before releasing the pinned pid/pgid identity. A
    /// failed reap becomes permanently unresolved rather than returning to
    /// `.owned`: no later cleanup path may signal a numeric identity that we
    /// could not prove was still ours.
    @discardableResult
    func reapLeader() -> Bool {
        lock.lock()
        switch state {
        case .released:
            lock.unlock()
            return true
        case .owned:
            state = .reaping
        case .reaping, .unresolved:
            lock.unlock()
            return false
        }
        lock.unlock()

        beforeReap()
        group.reapLeader()
        afterReap()

        let reapSucceeded: Bool
        let failureReason: String
        if let pid = group.pid {
            if let leaderIdentity {
                if let currentIdentity = processIdentity(pid) {
                    reapSucceeded = currentIdentity != leaderIdentity
                    failureReason = "group leader identity remained live after reap"
                } else {
                    reapSucceeded = processIsGone(pid)
                    failureReason = "group leader reap could not prove the pinned pid was gone"
                }
            } else {
                // Registration may intentionally precede spawn. Without a
                // live-child identity captured at init, release only when
                // both probes prove that the numeric pid is now absent; a
                // replacement identity remains unresolved and unsignalable.
                reapSucceeded = processIdentity(pid) == nil && processIsGone(pid)
                failureReason = "group leader reap could not prove the unpinned pid was gone"
            }
        } else {
            reapSucceeded = false
            failureReason = "group leader identity was unavailable before reap"
        }

        lock.lock()
        state = reapSucceeded ? .released : .unresolved(failureReason)
        lock.unlock()
        return reapSucceeded
    }

    /// Serializes the ownership check with the signal itself. Reaping first
    /// transitions to `.reaping` under this same lock, so a cancellation that
    /// observes that transition cannot signal the released numeric group.
    @discardableResult
    func terminateIfOwned(_ signal: Int32) -> TextFilterProcessGroup.SignalOutcome? {
        lock.lock()
        defer { lock.unlock() }
        guard case .owned = state else { return nil }
        return terminate(group, signal)
    }

    var isOwnershipReleased: Bool {
        lock.lock()
        defer { lock.unlock() }
        if case .released = state {
            return true
        }
        return false
    }

    var unresolvedReason: String? {
        lock.lock()
        defer { lock.unlock() }
        if case let .unresolved(reason) = state {
            return reason
        }
        return nil
    }
}

extension TextFilterFixtures {
    enum FixtureCleanupError: Error, CustomStringConvertible {
        case primaryAndCleanup(primary: String, cleanup: [String])
        case cleanupOnly([String])
        case cleanupUnresolved(primary: String?, reasons: [String])
        case cleanupTimedOut(primary: String?, timeout: Duration)

        var description: String {
            switch self {
            case let .primaryAndCleanup(primary, cleanup):
                return "fixture body failed with \(primary); cleanup also failed: \(cleanup.joined(separator: "; "))"
            case let .cleanupOnly(cleanup):
                return "fixture cleanup failed: \(cleanup.joined(separator: "; "))"
            case let .cleanupUnresolved(primary, reasons):
                let body = primary.map { " after body failure \($0)" } ?? ""
                return "fixture cleanup could not prove shutdown\(body): "
                    + "\(reasons.joined(separator: "; ")); directory preserved"
            case let .cleanupTimedOut(primary, timeout):
                let body = primary.map { " after body failure \($0)" } ?? ""
                return "fixture cleanup exceeded \(timeout)\(body); "
                    + "directory preserved because resources remain unresolved"
            }
        }
    }

    enum TaskOwnerError: Error, Equatable {
        case closed
    }

    enum OwnedProcessHandshakeError: Error, Equatable {
        case rejected
    }

    /// A fixture process lease is pinned to one PID and its Darwin process
    /// start identity for shutdown observation. Cleanup invokes the owning
    /// supervisor's teardown callback rather than signalling this PID after a
    /// check-then-signal race. Registration requires an explicit handoff from
    /// a genuine owned-child handle; teardown never discovers or adopts a PID
    /// from a fixture file.
    final class OwnedProcessLease: @unchecked Sendable {
        private let readinessTimeout: Duration
        private let probe: FixtureProcessProbe
        private let cancelSupervisor: @Sendable () -> Void
        private let lock = NSLock()
        private var identity: FixtureProcessIdentity?
        private var ownerPID: pid_t?
        private var cleanupRequested = false
        private var cancellationDispatched = false

        init(
            readinessTimeout: Duration,
            probe: FixtureProcessProbe,
            cancelSupervisor: @escaping @Sendable () -> Void = {}
        ) {
            self.readinessTimeout = readinessTimeout
            self.probe = probe
            self.cancelSupervisor = cancelSupervisor
        }

        /// Adopts an identity obtained from a genuine owned-child handle.
        /// Numeric self-PIDs, invalid start identities, stale observations,
        /// and PID records that do not match the current process table are
        /// rejected before the lease can observe or release them.
        func adopt(_ handoff: FixtureProcessHandoff) -> Bool {
            let candidate = handoff.identity
            guard candidate.pid > 0,
                  candidate.pid != getpid(),
                  handoff.ownerPID > 0,
                  handoff.ownerPID != getpid(),
                  candidate.startSeconds > 0 || candidate.startMicroseconds > 0,
                  probe.identity(candidate.pid) == candidate,
                  probe.parentPID(candidate.pid) == handoff.ownerPID
            else { return false }

            lock.lock()
            if identity == nil {
                identity = candidate
                ownerPID = handoff.ownerPID
            }
            let shouldCancel = cleanupRequested
            let pinnedIdentity = identity
            let pinnedOwnerPID = ownerPID
            lock.unlock()

            if shouldCancel {
                dispatchSupervisorCancellationIfNeeded()
            }
            return pinnedIdentity == candidate && pinnedOwnerPID == handoff.ownerPID
        }

        func requestCancellation() {
            lock.lock()
            cleanupRequested = true
            lock.unlock()
            dispatchSupervisorCancellationIfNeeded()
        }

        func join() async -> FixtureCleanupJoinResult {
            let readinessDeadline = ContinuousClock.now.advanced(by: readinessTimeout)
            var identityUnavailableDeadline: ContinuousClock.Instant?
            while !Task.isCancelled {
                let snapshot = snapshot()
                let pinnedIdentity = snapshot.identity

                guard let pinnedIdentity else {
                    if ContinuousClock.now >= readinessDeadline {
                        return .unresolved("owned child never completed its explicit PID/start-identity handoff")
                    }
                    try? await Task.sleep(for: .milliseconds(10))
                    continue
                }

                if probe.processIsGone(pinnedIdentity.pid) {
                    return .completed(nil)
                }
                guard let currentIdentity = probe.identity(pinnedIdentity.pid) else {
                    if let outcome = unavailableIdentityOutcome(
                        for: pinnedIdentity.pid,
                        deadline: &identityUnavailableDeadline
                    ) {
                        return outcome
                    }
                    try? await Task.sleep(for: .milliseconds(10))
                    continue
                }
                guard currentIdentity == pinnedIdentity else {
                    return .unresolved("owned PID was reused before cleanup could prove shutdown")
                }
                try? await Task.sleep(for: .milliseconds(10))
            }
            return .unresolved("owned process cleanup was cancelled before shutdown was proven")
        }

        private func dispatchSupervisorCancellationIfNeeded() {
            lock.lock()
            guard cleanupRequested, identity != nil, !cancellationDispatched else {
                lock.unlock()
                return
            }
            cancellationDispatched = true
            lock.unlock()
            cancelSupervisor()
        }

        private func unavailableIdentityOutcome(
            for pid: pid_t,
            deadline: inout ContinuousClock.Instant?
        ) -> FixtureCleanupJoinResult? {
            guard !probe.processIsZombie(pid) else { return .completed(nil) }
            if deadline == nil {
                deadline = ContinuousClock.now.advanced(by: .seconds(1))
            }
            guard let deadline, ContinuousClock.now >= deadline else { return nil }
            return .unresolved("owned process identity became unavailable before shutdown was proven")
        }

        private func snapshot() -> LeaseSnapshot {
            lock.lock()
            defer { lock.unlock() }
            return LeaseSnapshot(identity: identity)
        }
    }
}

extension TextFilterFixtures {
    private enum CleanupWaitResult: Sendable {
        case completed(FixtureCleanupReport)
        case timedOut
    }

    private actor CleanupGate {
        private var result: CleanupWaitResult?
        private var continuation: CheckedContinuation<CleanupWaitResult, Never>?

        func wait() async -> CleanupWaitResult {
            if let result {
                return result
            }
            return await withCheckedContinuation { continuation in
                self.continuation = continuation
            }
        }

        func complete(_ result: CleanupWaitResult) {
            guard self.result == nil else { return }
            self.result = result
            continuation?.resume(returning: result)
            continuation = nil
        }
    }

    /// Tracks unstructured async work which touches a fixture directory. The
    /// owner cancels and joins every tracked task before its directory scope
    /// can be torn down, including when the scoped operation throws or is
    /// cancelled.
    actor TaskOwner {
        private var cleanupRecords: [FixtureCleanupRecord] = []
        private var isClosed = false
        private var joinTask: Task<FixtureCleanupReport, Never>?

        func start<T: Sendable>(
            _ operation: @escaping @Sendable () async throws -> T
        ) throws -> Task<T, any Error> {
            guard !isClosed else { throw TaskOwnerError.closed }
            let completion = TaskJoinGate()
            let task = Task {
                do {
                    let result = try await operation()
                    await completion.complete(.finished(nil))
                    return result
                } catch {
                    await completion.complete(.finished(Self.cleanupDescription(for: error)))
                    throw error
                }
            }
            cleanupRecords.append(
                FixtureCleanupRecord(
                    cancel: { task.cancel() },
                    join: { await Self.join(completion: completion) }
                )
            )
            return task
        }

        func registerCleanup(
            cancel: @escaping @Sendable () -> Void,
            join: @escaping @Sendable () async -> FixtureCleanupJoinResult
        ) throws {
            guard !isClosed else { throw TaskOwnerError.closed }
            cleanupRecords.append(FixtureCleanupRecord(cancel: cancel, join: join))
        }

        /// Closes registration and cancels every owned resource synchronously
        /// before starting any asynchronous joins. The returned unstructured
        /// task joins all resources concurrently, so one resource waiting for
        /// another to observe cancellation cannot block that other resource's
        /// cancellation.
        func cancelAllAndCreateJoinTask() -> Task<FixtureCleanupReport, Never> {
            if let joinTask {
                return joinTask
            }
            isClosed = true
            let records = cleanupRecords
            cleanupRecords.removeAll()

            for record in records {
                record.cancel()
            }

            let joinTask = Task.detached {
                await withTaskGroup(of: FixtureCleanupJoinResult.self, returning: FixtureCleanupReport.self) { group in
                    for record in records {
                        group.addTask {
                            await record.join()
                        }
                    }
                    var failures: [String] = []
                    var unresolved: [String] = []
                    for await result in group {
                        switch result {
                        case let .completed(failure):
                            if let failure {
                                failures.append(failure)
                            }
                        case let .unresolved(reason):
                            unresolved.append(reason)
                        }
                    }
                    return FixtureCleanupReport(failures: failures, unresolved: unresolved)
                }
            }
            self.joinTask = joinTask
            return joinTask
        }

        private static func join(completion: TaskJoinGate) async -> FixtureCleanupJoinResult {
            let outcome = await withTaskCancellationHandler(operation: {
                await completion.wait()
            }, onCancel: {
                Task {
                    await completion.complete(.cancelled)
                }
            })
            switch outcome {
            case let .finished(failure):
                return .completed(failure)
            case .cancelled:
                return .unresolved("owned task did not finish after cancellation")
            }
        }

        private static func cleanupDescription(for error: any Error) -> String? {
            if error is CancellationError || (error as? TextFilterError) == .cancelled {
                return nil
            }
            return String(describing: error)
        }
    }
}

extension TextFilterFixtures {
    /// Owns a fixture directory for the complete lifetime of an asynchronous
    /// test operation. Callers that create unstructured tasks must use
    /// `withOwnedTemporaryDirectory` so those tasks can be joined explicitly.
    static func withTemporaryDirectory<T: Sendable>(
        _ operation: (URL) async throws -> T
    ) async throws -> T {
        try await withOwnedTemporaryDirectory { directory, _ in
            try await operation(directory)
        }
    }

    /// Owns a temporary directory and any unstructured tasks registered with
    /// its `TaskOwner`. Task cleanup always completes before the directory is
    /// removed, preserving the fixture for late process I/O and callbacks.
    static func withOwnedTemporaryDirectory<T: Sendable>(
        cleanupTimeout: Duration = .seconds(5),
        cleanupObserver: (@Sendable (CleanupPhase) -> Void)? = nil,
        _ operation: (URL, TaskOwner) async throws -> T
    ) async throws -> T {
        let directory = try makeTemporaryDirectory()
        let owner = TaskOwner()

        let bodyOutcome: Result<T, any Error>
        do {
            bodyOutcome = try await .success(operation(directory, owner))
        } catch {
            bodyOutcome = .failure(error)
        }

        cleanupObserver?(.cancellationRequested)
        let cancellationAndJoinTask = Task.detached {
            cleanupObserver?(.cancellationTaskStarted)
            let joinTask = await owner.cancelAllAndCreateJoinTask()
            cleanupObserver?(.cancellationReturned)
            return await withTaskCancellationHandler(operation: {
                await joinTask.value
            }, onCancel: {
                joinTask.cancel()
            })
        }
        let cleanupResult = await waitForCleanup(
            cancellationAndJoinTask, timeout: cleanupTimeout, observer: cleanupObserver
        )
        switch cleanupResult {
        case let .completed(report):
            if !report.unresolved.isEmpty {
                let reasons = report.unresolved + report.failures.map { "cleanup failure: \($0)" }
                throw unresolvedCleanupError(bodyOutcome: bodyOutcome, reasons: reasons)
            }
            return try completeCleanup(
                bodyOutcome: bodyOutcome,
                directory: directory,
                joinFailures: report.failures
            )
        case .timedOut:
            cancellationAndJoinTask.cancel()
            let primaryDescription: String? = switch bodyOutcome {
            case .success: nil
            case let .failure(error): String(describing: error)
            }
            throw FixtureCleanupError.cleanupTimedOut(primary: primaryDescription, timeout: cleanupTimeout)
        }
    }

    private static func unresolvedCleanupError<T>(
        bodyOutcome: Result<T, any Error>,
        reasons: [String]
    ) -> FixtureCleanupError {
        let primary: String? = switch bodyOutcome {
        case .success: nil
        case let .failure(error): String(describing: error)
        }
        return .cleanupUnresolved(primary: primary, reasons: reasons)
    }

    private static func completeCleanup<T: Sendable>(
        bodyOutcome: Result<T, any Error>,
        directory: URL,
        joinFailures: [String]
    ) throws -> T {
        var cleanupFailures = joinFailures
        if let removalFailure = removeTemporaryDirectory(at: directory) {
            cleanupFailures.append(removalFailure)
        }

        guard !cleanupFailures.isEmpty else { return try bodyOutcome.get() }
        switch bodyOutcome {
        case .success:
            throw FixtureCleanupError.cleanupOnly(cleanupFailures)
        case let .failure(primary):
            throw FixtureCleanupError.primaryAndCleanup(
                primary: String(describing: primary),
                cleanup: cleanupFailures
            )
        }
    }
}

extension TextFilterFixtures {
    enum CleanupPhase: String, Sendable {
        case cancellationRequested
        case cancellationTaskStarted
        case cancellationReturned
        case watchdogTaskStarted
        case watchdogSleepReturned
        case timeoutGateCompleted
        case gateWaitReturned
    }

    private static func waitForCleanup(
        _ joinTask: Task<FixtureCleanupReport, Never>,
        timeout: Duration,
        observer: (@Sendable (CleanupPhase) -> Void)?
    ) async -> CleanupWaitResult {
        let gate = CleanupGate()
        let completionObserver = Task.detached {
            await gate.complete(.completed(joinTask.value))
        }
        let watchdog = Task.detached {
            observer?(.watchdogTaskStarted)
            try? await Task.sleep(for: timeout)
            observer?(.watchdogSleepReturned)
            guard !Task.isCancelled else { return }
            await gate.complete(.timedOut)
            observer?(.timeoutGateCompleted)
        }
        let result = await gate.wait()
        observer?(.gateWaitReturned)
        watchdog.cancel()
        completionObserver.cancel()
        if case .timedOut = result {
            // Stop the aggregate join before returning the bounded timeout;
            // every child join is cancellation-aware, so the observer has a
            // finite completion path even when the directory is preserved.
            joinTask.cancel()
        }
        return result
    }

    private static func removeTemporaryDirectory(at directory: URL) -> String? {
        do {
            try FileManager.default.removeItem(at: directory)
            return nil
        } catch {
            return "could not remove \(directory.path): \(error)"
        }
    }

    static func registerOwnedProcessCleanup(
        handoff: FixtureProcessHandoff,
        with owner: TaskOwner,
        probe: FixtureProcessProbe = .darwin,
        readinessTimeout: Duration = .seconds(1),
        cancelSupervisor: @escaping @Sendable () -> Void = {}
    ) async throws -> OwnedProcessLease {
        let lease = makeOwnedProcessLease(
            readinessTimeout: readinessTimeout,
            probe: probe,
            cancelSupervisor: cancelSupervisor
        )
        guard lease.adopt(handoff) else {
            throw OwnedProcessHandshakeError.rejected
        }
        try await registerOwnedProcessCleanup(lease: lease, with: owner)
        return lease
    }

    static func makeOwnedProcessLease(
        readinessTimeout: Duration = .seconds(1),
        probe: FixtureProcessProbe = .darwin,
        cancelSupervisor: @escaping @Sendable () -> Void = {}
    ) -> OwnedProcessLease {
        OwnedProcessLease(
            readinessTimeout: readinessTimeout,
            probe: probe,
            cancelSupervisor: cancelSupervisor
        )
    }

    static func registerOwnedProcessCleanup(
        lease: OwnedProcessLease,
        with owner: TaskOwner
    ) async throws {
        try await owner.registerCleanup(
            cancel: { lease.requestCancellation() },
            join: { await lease.join() }
        )
    }

    static func ownedProcessIdentity(for pid: pid_t) -> FixtureProcessIdentity? {
        processIdentity(pid)
    }

    static func registerProcessGroupCleanup(
        _ group: TextFilterProcessGroup,
        with owner: TaskOwner
    ) async throws -> FixtureProcessGroupCleanup {
        let cleanup = FixtureProcessGroupCleanup(group: group)
        try await registerProcessGroupCleanup(
            cleanup: cleanup,
            with: owner,
            membershipState: { group.verifiedMembershipState() }
        )
        return cleanup
    }

    static func registerProcessGroupCleanup(
        cleanup: FixtureProcessGroupCleanup,
        with owner: TaskOwner,
        membershipState: @escaping @Sendable () -> TextFilterProcessGroup.MembershipState
    ) async throws {
        try await owner.registerCleanup(
            cancel: {
                _ = cleanup.terminateIfOwned(SIGKILL)
            },
            join: {
                if cleanup.isOwnershipReleased {
                    return .completed(nil)
                }
                if let reason = cleanup.unresolvedReason {
                    return .unresolved(reason)
                }
                while !Task.isCancelled {
                    if cleanup.isOwnershipReleased {
                        return .completed(nil)
                    }
                    if let reason = cleanup.unresolvedReason {
                        return .unresolved(reason)
                    }
                    let membership = membershipState()
                    if membership == .empty {
                        return cleanup.reapLeader()
                            ? .completed(nil)
                            : .unresolved(cleanup.unresolvedReason ?? "group leader reap was not proven")
                    }
                    // A group whose leader was already reaped no longer has
                    // a process-table row to inspect. A fresh ESRCH from the
                    // exact pinned group is the bounded proof that no group
                    // member remains; never accept an unconfirmed snapshot by
                    // itself.
                    if membership == .unconfirmed,
                       cleanup.terminateIfOwned(SIGKILL) == .groupIsGone {
                        return cleanup.reapLeader()
                            ? .completed(nil)
                            : .unresolved(cleanup.unresolvedReason ?? "group leader reap was not proven")
                    }
                    try? await Task.sleep(for: .milliseconds(20))
                }
                return .unresolved("owned process group cleanup was cancelled before shutdown was proven")
            }
        )
    }

    private static func reapSupervisorGroupIfEmpty(
        _ group: TextFilterProcessGroup,
        cleanup: FixtureProcessGroupCleanup
    ) -> FixtureCleanupJoinResult? {
        guard group.verifiedMembershipState() == .empty else { return nil }
        return cleanup.reapLeader()
            ? .completed(nil)
            : .unresolved(cleanup.unresolvedReason ?? "supervisor fallback reap was not proven")
    }

    private static func signalSupervisorGroup(
        _ signal: Int32,
        cleanup: FixtureProcessGroupCleanup
    ) -> FixtureCleanupJoinResult? {
        guard let outcome = cleanup.terminateIfOwned(signal) else {
            return .unresolved(
                cleanup.unresolvedReason ?? "supervisor fallback lost group ownership before signal"
            )
        }
        guard outcome == .groupIsGone else { return nil }
        return cleanup.reapLeader()
            ? .completed(nil)
            : .unresolved(cleanup.unresolvedReason ?? "supervisor fallback reap was not proven")
    }

    private static func joinSupervisorFallback(
        group: TextFilterProcessGroup,
        cleanup: FixtureProcessGroupCleanup,
        grace: Duration
    ) async -> FixtureCleanupJoinResult {
        let graceDeadline = ContinuousClock.now.advanced(by: grace)
        while !Task.isCancelled, ContinuousClock.now < graceDeadline {
            if let result = reapSupervisorGroupIfEmpty(group, cleanup: cleanup) {
                return result
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        guard !Task.isCancelled else {
            return .unresolved("supervisor fallback cleanup was cancelled before shutdown was proven")
        }
        if let result = signalSupervisorGroup(SIGTERM, cleanup: cleanup) {
            return result
        }

        let terminationDeadline = ContinuousClock.now.advanced(by: .seconds(1))
        while !Task.isCancelled, ContinuousClock.now < terminationDeadline {
            if let result = reapSupervisorGroupIfEmpty(group, cleanup: cleanup) {
                return result
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        guard !Task.isCancelled else {
            return .unresolved("supervisor fallback cleanup was cancelled before escalation completed")
        }
        if let result = signalSupervisorGroup(SIGKILL, cleanup: cleanup) {
            return result
        }

        let killDeadline = ContinuousClock.now.advanced(by: .seconds(1))
        while !Task.isCancelled, ContinuousClock.now < killDeadline {
            if let result = reapSupervisorGroupIfEmpty(group, cleanup: cleanup) {
                return result
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return .unresolved("supervisor fallback cleanup could not prove group shutdown")
    }

    static func registerSupervisorFallbackCleanup(
        _ group: TextFilterProcessGroup,
        with owner: TaskOwner,
        grace: Duration = .milliseconds(100)
    ) async throws {
        let cleanup = FixtureProcessGroupCleanup(group: group)
        try await owner.registerCleanup(
            cancel: {},
            join: { await joinSupervisorFallback(group: group, cleanup: cleanup, grace: grace) }
        )
    }

    static func processIdentity(_ pid: pid_t) -> FixtureProcessIdentity? {
        var info = proc_bsdinfo()
        let result = withUnsafeMutablePointer(to: &info) {
            proc_pidinfo(
                pid,
                PROC_PIDTBSDINFO,
                0,
                $0,
                Int32(MemoryLayout<proc_bsdinfo>.size)
            )
        }
        guard result == MemoryLayout<proc_bsdinfo>.size, info.pbi_pid == pid else { return nil }
        return FixtureProcessIdentity(
            pid: pid,
            startSeconds: info.pbi_start_tvsec,
            startMicroseconds: info.pbi_start_tvusec
        )
    }

    static func processParentPID(_ pid: pid_t) -> pid_t? {
        var info = proc_bsdinfo()
        let result = withUnsafeMutablePointer(to: &info) {
            proc_pidinfo(
                pid,
                PROC_PIDTBSDINFO,
                0,
                $0,
                Int32(MemoryLayout<proc_bsdinfo>.size)
            )
        }
        guard result == MemoryLayout<proc_bsdinfo>.size,
              info.pbi_pid == pid,
              info.pbi_ppid <= UInt32(pid_t.max)
        else { return nil }
        return pid_t(info.pbi_ppid)
    }

    static func processGroupID(_ pid: pid_t) -> pid_t? {
        let groupID = getpgid(pid)
        return groupID >= 0 ? groupID : nil
    }

    static func processIsZombie(_ pid: pid_t) -> Bool {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        let result = withUnsafeMutableBytes(of: &info) { rawBuffer in
            sysctl(&mib, u_int(mib.count), rawBuffer.baseAddress, &size, nil, 0)
        }
        return result == 0 && info.kp_proc.p_stat == SZOMB
    }
}

// swiftlint:enable file_length
