import Foundation
import Testing
@testable import TextFilters

/// Deterministic, process-free coverage of `TextFilterTerminalState`'s
/// one-shot commit rules (second-adversarial-pass findings #1/#3). Driving
/// exact event orderings here — rather than only via real subprocess timing
/// — proves the invariants hold regardless of scheduler luck.
@Suite("TextFilterTerminalState")
struct TextFilterTerminalStateTests {
    // MARK: - Finding #1: `.exited` requires every fact, never fewer

    @Test func exitWithoutEitherEOFNeverCommits() {
        let state = TextFilterTerminalState()
        state.recordChildExited(0)
        #expect(state.committedVerdict == nil)
    }

    @Test func exitWithOnlyStdoutEOFNeverCommits() {
        let state = TextFilterTerminalState()
        state.recordChildExited(0)
        state.recordStdoutEOF()
        #expect(state.committedVerdict == nil, "stdout EOF alone must not be enough without stderr EOF too")
    }

    @Test func exitWithOnlyStderrEOFNeverCommits() {
        let state = TextFilterTerminalState()
        state.recordChildExited(0)
        state.recordStderrEOF()
        #expect(state.committedVerdict == nil, "stderr EOF alone must not be enough without stdout EOF too")
    }

    @Test func allThreeFactsInAnyOrderCommitExitedExactlyOnce() {
        func run(_ actions: (TextFilterTerminalState) -> Void) -> TextFilterTerminalState.Verdict? {
            let state = TextFilterTerminalState()
            actions(state)
            return state.committedVerdict
        }

        #expect(run { state in
            state.recordChildExited(0); state.recordStdoutEOF(); state.recordStderrEOF()
        } == .exited(0))
        #expect(run { state in
            state.recordChildExited(0); state.recordStderrEOF(); state.recordStdoutEOF()
        } == .exited(0))
        #expect(run { state in
            state.recordStdoutEOF(); state.recordChildExited(0); state.recordStderrEOF()
        } == .exited(0))
        #expect(run { state in
            state.recordStdoutEOF(); state.recordStderrEOF(); state.recordChildExited(0)
        } == .exited(0))
        #expect(run { state in
            state.recordStderrEOF(); state.recordStdoutEOF(); state.recordChildExited(0)
        } == .exited(0))
        #expect(run { state in
            state.recordStderrEOF(); state.recordChildExited(0); state.recordStdoutEOF()
        } == .exited(0))
    }

    @Test func noTimerOrRequestCanFabricateAnExitedVerdictWithoutRealEOF() async {
        // The whole point of finding #1: nothing except the three real
        // facts can ever produce `.exited`. Simulate a "timer fired" by
        // simply doing nothing — there is no API on this type that lets a
        // caller assert EOF without it actually having happened.
        let state = TextFilterTerminalState()
        state.recordChildExited(0)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(state.committedVerdict == nil)
    }

    // MARK: - Finding #3: one-shot commit, first verdict wins permanently

    @Test func normalCompletionThenLateTimeoutRequestKeepsSuccess() {
        let state = TextFilterTerminalState()
        state.recordChildExited(0)
        state.recordStdoutEOF()
        state.recordStderrEOF()
        #expect(state.committedVerdict == .exited(0))

        let committed = state.requestVerdict(.timedOut)
        #expect(committed == false, "a verdict must not be replaceable once committed")
        #expect(state.committedVerdict == .exited(0), "success → later timeout must remain success")
    }

    @Test func normalCompletionThenLateCancellationRequestKeepsSuccess() {
        let state = TextFilterTerminalState()
        state.recordChildExited(0)
        state.recordStdoutEOF()
        state.recordStderrEOF()

        #expect(state.requestVerdict(.cancelled) == false)
        #expect(state.committedVerdict == .exited(0))
    }

    @Test func timeoutThenLateZeroExitPlusEOFsStaysTimedOut() {
        let state = TextFilterTerminalState()
        #expect(state.requestVerdict(.timedOut) == true)

        // The watchdog "won" the race, but the process happens to still
        // report a clean exit and drain shortly after.
        state.recordChildExited(0)
        state.recordStdoutEOF()
        state.recordStderrEOF()

        #expect(state.committedVerdict == .timedOut, "timeout → later exit 0 must remain timeout")
    }

    @Test func cancellationThenLateZeroExitPlusEOFsStaysCancelled() {
        let state = TextFilterTerminalState()
        #expect(state.requestVerdict(.cancelled) == true)

        state.recordChildExited(0)
        state.recordStdoutEOF()
        state.recordStderrEOF()

        #expect(state.committedVerdict == .cancelled, "cancel → later exit 0 must remain cancel")
    }

    @Test func oversizedThenLateZeroExitPlusEOFsStaysOversized() {
        let state = TextFilterTerminalState()
        #expect(state.requestVerdict(.oversized) == true)

        state.recordChildExited(0)
        state.recordStdoutEOF()
        state.recordStderrEOF()

        #expect(state.committedVerdict == .oversized, "oversize → later exit 0 must remain oversize")
    }

    @Test func onlyTheFirstOfTwoRacingForcedRequestsCommits() {
        let state = TextFilterTerminalState()
        #expect(state.requestVerdict(.timedOut) == true)
        #expect(state.requestVerdict(.cancelled) == false)
        #expect(state.committedVerdict == .timedOut)
    }

    @Test func waitReturnsImmediatelyWhenAlreadyCommittedBeforeItIsCalled() async {
        let state = TextFilterTerminalState()
        state.requestVerdict(.oversized)
        let verdict = await state.wait()
        #expect(verdict == .oversized)
    }

    @Test func waitSuspendsUntilACommitHappensLater() async throws {
        let state = TextFilterTerminalState()
        async let verdict = state.wait()
        try await Task.sleep(for: .milliseconds(50))
        state.requestVerdict(.cancelled)
        let result = await verdict
        #expect(result == .cancelled)
    }
}
