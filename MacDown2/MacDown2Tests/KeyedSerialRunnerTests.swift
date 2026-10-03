@testable import MacDown2
import Testing

/// Review pass 1: two near-simultaneous opens of one file both passed the "already open?"
/// check and created two windows for it.
@MainActor
struct KeyedSerialRunnerTests {
    @MainActor
    private final class Recorder {
        var events: [String] = []
        var running = 0
        var maxRunning = 0

        func work(_ name: String) async {
            running += 1
            maxRunning = max(maxRunning, running)
            events.append("start \(name)")
            await Task.yield()
            await Task.yield()
            events.append("end \(name)")
            running -= 1
        }
    }

    @Test func operationsForTheSameKeyNeverOverlapAndKeepSubmissionOrder() async {
        let runner = KeyedSerialRunner<String>()
        let recorder = Recorder()

        let tasks = ["1", "2", "3"].map { name in
            Task { @MainActor in await runner.run(key: "file") { await recorder.work(name) } }
        }
        for task in tasks {
            await task.value
        }

        #expect(recorder.maxRunning == 1)
        #expect(recorder.events == ["start 1", "end 1", "start 2", "end 2", "start 3", "end 3"])
    }

    @Test func differentKeysRunConcurrently() async {
        let runner = KeyedSerialRunner<String>()
        let recorder = Recorder()

        let tasks = ["a", "b"].map { key in
            Task { @MainActor in await runner.run(key: key) { await recorder.work(key) } }
        }
        for task in tasks {
            await task.value
        }

        #expect(recorder.maxRunning == 2)
    }

    @Test func aFinishedKeyCanBeRunAgain() async {
        let runner = KeyedSerialRunner<String>()
        let recorder = Recorder()
        await runner.run(key: "x") { await recorder.work("1") }
        await runner.run(key: "x") { await recorder.work("2") }
        #expect(recorder.events.count == 4)
    }
}
