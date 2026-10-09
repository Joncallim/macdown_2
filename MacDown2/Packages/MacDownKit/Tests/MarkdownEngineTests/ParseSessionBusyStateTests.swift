import Foundation
@testable import MarkdownEngine
import Testing

/// An engine whose every `parse` call suspends until the test releases that
/// specific call, so overlapping parses are interleaved deterministically
/// (no sleeps, no polling for a momentary state).
actor GatedParseEngine: ParseExecuting {
    private var started = 0
    private var startWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private var gates: [Int: CheckedContinuation<Void, Never>] = [:]
    private var released: Set<Int> = []

    func parse(_ text: String, options: MarkdownParseOptions, revision: Int) async throws -> MarkdownDocument {
        started += 1
        let call = started
        let ready = startWaiters.filter { $0.count <= started }
        startWaiters.removeAll { $0.count <= started }
        for waiter in ready {
            waiter.continuation.resume()
        }
        if !released.contains(call) {
            await withCheckedContinuation { gates[call] = $0 }
        }
        return MarkdownDocument(
            body: text,
            bodyLineOffset: 0,
            blocks: [],
            headings: [],
            frontMatter: nil,
            sourceMap: SourceMap(text: text),
            revision: revision,
            options: options
        )
    }

    func waitUntilStarted(_ count: Int) async {
        if started >= count {
            return
        }
        await withCheckedContinuation { startWaiters.append((count, $0)) }
    }

    func release(call: Int) {
        released.insert(call)
        gates.removeValue(forKey: call)?.resume()
    }
}

@MainActor
struct ParseSessionBusyStateTests {
    /// An older immediate parse completing while a newer one is still
    /// outstanding must not report the session idle.
    @Test func olderImmediateCompletionKeepsSessionBusyWhileNewerParseIsOutstanding() async {
        let engine = GatedParseEngine()
        let session = MarkdownParseSession(engine: engine, debounce: .seconds(10))

        let first = Task { await session.parseNow("first") }
        await engine.waitUntilStarted(1)
        let second = Task { await session.parseNow("second") }
        await engine.waitUntilStarted(2)

        await engine.release(call: 1)
        _ = await first.value
        #expect(session.isParsing, "the second immediate parse is still outstanding")

        await engine.release(call: 2)
        _ = await second.value
        #expect(!session.isParsing, "the session is idle once every parse has finished")
        #expect(session.document?.body == "second")
    }

    /// The newer parse finishing first leaves the superseded one running;
    /// the session stays busy until it is also done and then settles idle
    /// (the superseded completion must not leave it stuck busy).
    @Test func newerImmediateFinishingFirstStillSettlesIdle() async {
        let engine = GatedParseEngine()
        let session = MarkdownParseSession(engine: engine, debounce: .seconds(10))

        let first = Task { await session.parseNow("first") }
        await engine.waitUntilStarted(1)
        let second = Task { await session.parseNow("second") }
        await engine.waitUntilStarted(2)

        await engine.release(call: 2)
        _ = await second.value
        #expect(session.isParsing, "the superseded parse has not returned yet")

        await engine.release(call: 1)
        _ = await first.value
        #expect(!session.isParsing)
        #expect(session.document?.body == "second", "the superseded result must not overwrite the newer one")
    }

    /// `cancelPending` while an immediate parse is in flight must not leave
    /// the busy flag stuck once that parse returns.
    @Test func cancelPendingDuringImmediateParseSettlesIdle() async {
        let engine = GatedParseEngine()
        let session = MarkdownParseSession(engine: engine, debounce: .seconds(10))

        let parse = Task { await session.parseNow("only") }
        await engine.waitUntilStarted(1)
        session.cancelPending()
        await engine.release(call: 1)
        _ = await parse.value
        #expect(!session.isParsing)
    }
}
