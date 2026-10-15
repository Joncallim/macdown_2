import Darwin
import Foundation
import Testing
@testable import TextFilters

@Suite("TextFilter owned-process handshakes")
struct TextFilterFixtureHandshakeTests {
    private final class FakeProcessState: @unchecked Sendable {
        private let lock = NSLock()
        private var currentIdentity: FixtureProcessIdentity?
        private var currentParentPID: pid_t?
        private var gone = false
        private var zombie = false
        private var supervisorCancellations = 0

        init(identity: FixtureProcessIdentity?, parentPID: pid_t?) {
            currentIdentity = identity
            currentParentPID = parentPID
        }

        var supervisorCancellationCount: Int {
            lock.lock()
            defer { lock.unlock() }
            return supervisorCancellations
        }

        func cancelSupervisor() {
            lock.lock()
            supervisorCancellations += 1
            lock.unlock()
        }

        func replaceIdentity(_ identity: FixtureProcessIdentity?) {
            lock.lock()
            currentIdentity = identity
            lock.unlock()
        }

        func probe() -> FixtureProcessProbe {
            FixtureProcessProbe(
                identity: { [weak self] pid in
                    self?.read { identity in identity?.pid == pid ? identity : nil }
                },
                parentPID: { [weak self] pid in
                    self?.readParent(pid: pid)
                },
                processIsGone: { [weak self] _ in
                    self?.read { _ in self?.gone ?? true } ?? true
                },
                processIsZombie: { [weak self] _ in
                    self?.read { _ in self?.zombie ?? false } ?? false
                }
            )
        }

        private func read<T>(_ body: (FixtureProcessIdentity?) -> T) -> T {
            lock.lock()
            defer { lock.unlock() }
            return body(currentIdentity)
        }

        private func readParent(pid: pid_t) -> pid_t? {
            lock.lock()
            defer { lock.unlock() }
            return currentIdentity?.pid == pid ? currentParentPID : nil
        }
    }

    private func identity(pid: pid_t, seconds: UInt64 = 10, microseconds: UInt64 = 1) -> FixtureProcessIdentity {
        FixtureProcessIdentity(pid: pid, startSeconds: seconds, startMicroseconds: microseconds)
    }

    @Test func staleHandshakeIsRejectedBeforeAdoption() {
        let expected = identity(pid: 31001)
        let replacement = identity(pid: 31001, seconds: 11)
        let state = FakeProcessState(identity: replacement, parentPID: 32001)
        let lease = TextFilterFixtures.OwnedProcessLease(
            readinessTimeout: .milliseconds(1),
            probe: state.probe(),
            cancelSupervisor: { state.cancelSupervisor() }
        )

        #expect(!lease.adopt(FixtureProcessHandoff(identity: expected, ownerPID: 32001)))
        lease.requestCancellation()
        #expect(state.supervisorCancellationCount == 0)
    }

    @Test func pidReuseAfterAdoptionIsNeverSignalled() async {
        let expected = identity(pid: 31002)
        let replacement = identity(pid: 31002, seconds: 11)
        let state = FakeProcessState(identity: expected, parentPID: 32002)
        let lease = TextFilterFixtures.OwnedProcessLease(
            readinessTimeout: .milliseconds(10),
            probe: state.probe(),
            cancelSupervisor: { state.cancelSupervisor() }
        )

        #expect(lease.adopt(FixtureProcessHandoff(identity: expected, ownerPID: 32002)))
        state.replaceIdentity(replacement)
        lease.requestCancellation()
        let result = await lease.join()

        guard case let .unresolved(reason) = result else {
            Issue.record("PID reuse must make cleanup unresolved")
            return
        }
        #expect(reason.contains("reused"))
        #expect(state.supervisorCancellationCount == 1)
    }

    @Test func selfPIDIsRejectedBeforeSignal() async {
        let selfIdentity = identity(pid: getpid())
        let state = FakeProcessState(identity: selfIdentity, parentPID: 32003)
        let lease = TextFilterFixtures.OwnedProcessLease(
            readinessTimeout: .milliseconds(10),
            probe: state.probe(),
            cancelSupervisor: { state.cancelSupervisor() }
        )

        #expect(!lease.adopt(FixtureProcessHandoff(identity: selfIdentity, ownerPID: 32003)))
        lease.requestCancellation()
        let result = await lease.join()

        guard case let .unresolved(reason) = result else {
            Issue.record("self-PID adoption must remain unresolved")
            return
        }
        #expect(reason.contains("handoff"))
        #expect(state.supervisorCancellationCount == 0)
    }

    @Test func lateArrivalWithoutExplicitAdoptionIsNeverSignalled() async {
        let lateIdentity = identity(pid: 31003)
        let state = FakeProcessState(identity: nil, parentPID: 32004)
        let lease = TextFilterFixtures.OwnedProcessLease(
            readinessTimeout: .milliseconds(10),
            probe: state.probe(),
            cancelSupervisor: { state.cancelSupervisor() }
        )

        lease.requestCancellation()
        state.replaceIdentity(lateIdentity)
        let result = await lease.join()

        guard case let .unresolved(reason) = result else {
            Issue.record("late unadopted arrival must remain unresolved")
            return
        }
        #expect(reason.contains("handoff"))
        #expect(state.supervisorCancellationCount == 0)
    }
}
