import Foundation

/// Manually advances idle-restore sleeps while keeping the real editor and highlighter.
@MainActor
final class ManualRestoreSleeper {
    private struct Waiter {
        let deadline: Duration
        let continuation: CheckedContinuation<Void, any Error>
    }

    private(set) var now: Duration = .zero
    private(set) var allocatedIDs: [Int] = []
    private(set) var registeredIDs: [Int] = []
    private(set) var completedIDs: [Int] = []
    private(set) var cancelledIDs: Set<Int> = []
    private var nextID = 0
    private var isTerminated = false
    private var deadlines: [Int: Duration] = [:]
    private var waiters: [Int: Waiter] = [:]
    private var heldRegistrationIDs: Set<Int> = []
    private var registrationReleases: [Int: CheckedContinuation<Void, Never>] = [:]

    var sleepClosure: @MainActor (Duration) async throws -> Void {
        { [weak self] duration in
            guard let self else { return }
            try await self.sleep(for: duration)
        }
    }

    func holdNextRegistration() {
        heldRegistrationIDs.insert(nextID + 1)
    }

    func sleep(for duration: Duration) async throws {
        nextID += 1
        let id = nextID
        allocatedIDs.append(id)

        try await withTaskCancellationHandler {
            if !isTerminated, heldRegistrationIDs.remove(id) != nil {
                await withCheckedContinuation { registrationReleases[id] = $0 }
            }
            try await withCheckedThrowingContinuation { continuation in
                registeredIDs.append(id)
                let deadline = now + duration
                deadlines[id] = deadline
                if isTerminated || deadline <= now {
                    completedIDs.append(id)
                    continuation.resume()
                } else {
                    waiters[id] = Waiter(deadline: deadline, continuation: continuation)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard let self else { return }
                cancelledIDs.insert(id)
            }
        }
    }

    func waitForAllocation(after count: Int, timeout: Duration = .seconds(5)) async -> Int? {
        await wait(timeout: timeout) { allocatedIDs.count > count }
            ? allocatedIDs[count] : nil
    }

    func waitForRegistration(_ id: Int, timeout: Duration = .seconds(5)) async -> Bool {
        await wait(timeout: timeout) { registeredIDs.contains(id) }
    }

    func waitForCancellation(_ id: Int, timeout: Duration = .seconds(5)) async -> Bool {
        await wait(timeout: timeout) { cancelledIDs.contains(id) }
    }

    func releaseRegistration(_ id: Int) -> Bool {
        guard let continuation = registrationReleases.removeValue(forKey: id) else { return false }
        continuation.resume()
        return true
    }

    func advance(by duration: Duration) -> [Int] {
        now += duration
        let due = waiters.filter { $0.value.deadline <= now }.map(\.key).sorted()
        for id in due {
            _ = release(id)
        }
        return due
    }

    func release(_ id: Int) -> Bool {
        guard let waiter = waiters.removeValue(forKey: id) else { return false }
        completedIDs.append(id)
        waiter.continuation.resume()
        return true
    }

    func deadline(for id: Int) -> Duration? {
        deadlines[id]
    }

    func terminateAndDrain(_ tasks: [Task<Void, Never>]) async {
        isTerminated = true
        heldRegistrationIDs.removeAll()
        // A normal return from a test sleep must not start another restore or
        // marked-text retry while the fixture is being dismantled.
        for task in tasks {
            task.cancel()
        }
        for id in registrationReleases.keys.sorted() {
            _ = releaseRegistration(id)
        }
        for id in waiters.keys.sorted() {
            _ = release(id)
        }
        for task in tasks {
            await task.value
        }
    }

    private func wait(timeout: Duration, _ condition: () -> Bool) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition(), !isTerminated, clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }
}
