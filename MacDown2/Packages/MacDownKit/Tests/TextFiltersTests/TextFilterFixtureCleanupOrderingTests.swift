import Foundation
import Testing
@testable import TextFilters

@Suite("TextFilter fixture cleanup ordering")
struct TextFilterFixtureCleanupOrderingTests {
    @Test func watchdogStartingAfterItsAbsoluteDeadlineTimesOutImmediately() async {
        let timeout: Duration = .milliseconds(300)
        let run = CleanupWatchdogRun(timeout: timeout, delayWatchdogStart: true)
        #expect(await run.startBarrier.waitUntilStarted())
        run.virtualNow.advance(by: .seconds(1))
        run.startBarrier.release()
        // The generous real-time limit is only a deadlock guard. The exact
        // requested deadline and timeout outcome are the regression oracle.
        #expect(await run.deadlineProbe.waitForRequest() == run.base.advanced(by: timeout))
        #expect(await run.outcome.wait() == .timedOut(timeout))
        #expect(await run.finish() == true)
    }

    @Test func completionWinsAfterDeadlineWhileWatchdogIsHeld() async {
        let timeout: Duration = .milliseconds(300)
        let run = CleanupWatchdogRun(timeout: timeout)
        #expect(await run.deadlineProbe.waitForRequest() == run.base.advanced(by: timeout))
        #expect(await run.join.waitUntilStarted())
        run.virtualNow.advance(by: .seconds(1))
        await run.join.release()
        // Preserve existing first-arrival semantics even after the deadline.
        #expect(await run.outcome.wait() == .completed)
        #expect(await run.finish() == false)
    }

    @Test func timeoutWinsBeforeLateJoin() async {
        let timeout: Duration = .milliseconds(300)
        let run = CleanupWatchdogRun(timeout: timeout)
        #expect(await run.deadlineProbe.waitForRequest() == run.base.advanced(by: timeout))
        #expect(await run.join.waitUntilStarted())
        run.virtualNow.advance(by: .seconds(1))
        await run.deadlineProbe.releaseSleep()
        #expect(await run.outcome.wait() == .timedOut(timeout))
        #expect(await run.finish() == true)
    }

    @Test(arguments: [false, true])
    func cleanupGateKeepsFirstResultAfterAcknowledgingBothAttempts(timeoutFirst: Bool) async {
        let gate = TextFilterFixtures.CleanupGate()
        let completion = TextFilterFixtures.CleanupWaitResult.completed(
            FixtureCleanupReport(failures: ["first completion"], unresolved: [])
        )
        let first: TextFilterFixtures.CleanupWaitResult = timeoutFirst ? .timedOut : completion
        let second: TextFilterFixtures.CleanupWaitResult = timeoutFirst ? completion : .timedOut
        await gate.complete(first)
        await assertGateResult(gate.wait(), timeoutFirst: timeoutFirst)
        // Awaiting this actor call proves the competing result reached the
        // actual gate, unlike a canceled watchdog that exits before attempting it.
        await gate.complete(second)
        await assertGateResult(gate.wait(), timeoutFirst: timeoutFirst)
    }

    @Test func failedObservationStillReleasesAndJoinsAllHeldWork() async {
        let run = CleanupWatchdogRun(timeout: .milliseconds(300), delayWatchdogStart: true)
        #expect(await run.startBarrier.waitUntilStarted())
        #expect(await run.join.waitUntilStarted())
        #expect(await run.outcome.wait(timeout: .milliseconds(25)) == nil)
        // Either result may win when both barriers are released. What matters
        // here is that teardown finishes and removes its own fixture afterward.
        #expect(await run.finish() != nil)
        #expect(await run.outcome.wait() != nil)
    }

    private func assertGateResult(_ result: TextFilterFixtures.CleanupWaitResult, timeoutFirst: Bool) {
        switch result {
        case .timedOut:
            #expect(timeoutFirst)
        case let .completed(report):
            #expect(!timeoutFirst)
            #expect(report.failures == ["first completion"])
            #expect(report.unresolved.isEmpty)
        }
    }
}
