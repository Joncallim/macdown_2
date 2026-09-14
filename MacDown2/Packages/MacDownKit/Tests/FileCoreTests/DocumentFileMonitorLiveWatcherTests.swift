@testable import FileCore
import Foundation
import Testing

/// #59: every existing `DocumentFileMonitor` test drives it with a FAKE
/// `DocumentDirectoryWatching` (`MonitorWatcher`) that fires signals by
/// direct method call — none of them exercise the REAL, production
/// `LiveDocumentDirectoryWatcher` (the actual kqueue/`DispatchSourceFileSystemObject`
/// mechanism). #59 reports that in real Release-app and XCUITest use, the
/// UI never observes an external deletion at all. The issue's own suggested
/// next step is to determine whether the underlying kqueue event fires at
/// all, independent of the UI/XCUITest layer above it — this suite answers
/// exactly that question, end to end through the REAL `DocumentFileMonitor`
/// (default `init`, so `LiveDocumentDirectoryWatcher` + `DocumentFileProbe`
/// + a real `Task.sleep`-based debounce), against a REAL file on disk, with
/// no UI/XCUITest/Accessibility-automation dependency at all.
@Suite("Document file monitor — real watcher (#59)")
struct DocumentFileMonitorLiveWatcherTests {
    private actor Recorder {
        private(set) var observations: [DocumentFileObservation] = []
        func append(_ observation: DocumentFileObservation) {
            observations.append(observation)
        }
    }

    private func makeFile(named name: String = "external.md", contents: String = "# Original\n") throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test func realWatcherDetectsExternalDeletionWithinAFewSeconds() async throws {
        let fileURL = try makeFile()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let monitor = DocumentFileMonitor()
        let recorder = Recorder()
        try await monitor.bind(to: fileURL, priorFileObjectID: nil) { observation in
            Task { await recorder.append(observation) }
        }
        await waitUntil({ await recorder.observations.count == 1 }, timeout: .seconds(5))
        let initialCount = await recorder.observations.count
        #expect(initialCount == 1, "the initial bind-time probe must observe the file exists before we delete it")

        // The exact repro from #59: delete the backing file externally
        // while the document is open — simulating `rm` or Finder trash.
        try FileManager.default.removeItem(at: fileURL)

        // Generous timeout: production's own debounce is 150ms, plus a
        // 75ms missing-confirmation re-probe (#59's own code trace) — a
        // real kqueue event, if it fires, should be observed well within
        // 5 seconds even under load. If this times out, the kqueue
        // mechanism itself is not delivering the event in this
        // environment — the exact ambiguity #59 asks to resolve.
        await waitUntil({
            await recorder.observations.contains {
                if case .missing = $0 {
                    return true
                }
                return false
            }
        }, timeout: .seconds(5))

        let observations = await recorder.observations
        let sawMissing = observations.contains {
            if case .missing = $0 {
                return true
            }
            return false
        }
        #expect(sawMissing, "expected a .missing observation after real external deletion; got: \(observations)")
    }

    /// Reproduces `ExternalFileController`'s EXACT binding shape rather than
    /// the simpler `onObservation`-based binding the test above uses:
    /// `onObservation` is a no-op, and only `onContext` is wired up, whose
    /// guard re-fetches `monitor.currentRequestGeneration()` ASYNCHRONOUSLY
    /// on the MainActor — a value that can have already moved on again by
    /// the time that re-check actually runs — instead of trusting the
    /// `requestGeneration` already captured on the context at emit time.
    /// If this test fails while the simpler one above passes, that
    /// generation re-check is the actual #59 bug, not the watcher mechanism.
    @Test @MainActor func externalFileControllerStyleBindingDetectsExternalDeletion() async throws {
        let fileURL = try makeFile()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let monitor = DocumentFileMonitor()
        let recorder = Recorder()
        try await monitor.bind(
            to: fileURL,
            priorFileObjectID: nil,
            onObservation: { _ in },
            onHealthChange: { _ in },
            onContext: { context in
                Task { @MainActor in
                    let currentRequest = await monitor.currentRequestGeneration()
                    guard context.requestGeneration == currentRequest else { return }
                    await recorder.append(context.observation)
                }
            }
        )
        await waitUntil({ await recorder.observations.count == 1 }, timeout: .seconds(5))

        try FileManager.default.removeItem(at: fileURL)

        await waitUntil({
            await recorder.observations.contains {
                if case .missing = $0 {
                    return true
                }
                return false
            }
        }, timeout: .seconds(5))

        let observations = await recorder.observations
        let sawMissing = observations.contains {
            if case .missing = $0 {
                return true
            }
            return false
        }
        #expect(sawMissing, "context-generation re-check dropped the .missing observation; got: \(observations)")
    }

    @Test func realWatcherDetectsAtomicReplacement() async throws {
        let fileURL = try makeFile()
        defer { try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent()) }

        let monitor = DocumentFileMonitor()
        let recorder = Recorder()
        try await monitor.bind(to: fileURL, priorFileObjectID: nil) { observation in
            Task { await recorder.append(observation) }
        }
        await waitUntil({ await recorder.observations.count == 1 }, timeout: .seconds(5))

        // Common atomic-save pattern: write to a sibling temp file, then
        // replace the original — what many editors (including this app's
        // own save path) and command-line tools do instead of a plain
        // in-place write.
        let replacementURL = fileURL.deletingLastPathComponent().appendingPathComponent("external.md.tmp")
        try "# Disk Version\n".write(to: replacementURL, atomically: true, encoding: .utf8)
        _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: replacementURL)

        await waitUntil({
            await recorder.observations.contains {
                if case let .available(snapshot) = $0 {
                    return snapshot.text == "# Disk Version\n"
                }
                return false
            }
        }, timeout: .seconds(5))

        let observations = await recorder.observations
        let sawReplacement = observations.contains {
            if case let .available(snapshot) = $0 {
                return snapshot.text == "# Disk Version\n"
            }
            return false
        }
        #expect(sawReplacement, "expected an .available observation with the replaced content; got: \(observations)")
    }
}
