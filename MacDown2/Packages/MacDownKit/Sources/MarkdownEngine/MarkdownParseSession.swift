import Foundation
import Observation
import os.log

/// Per-document debounce + publish. One per open document, owned via the store.
@MainActor
@Observable
public final class MarkdownParseSession {
    /// Latest completed parse. nil until the first parse completes.
    public private(set) var document: MarkdownDocument?

    /// True while a parse Task is pending or running (drives subtle UI later).
    public private(set) var isParsing: Bool = false

    /// Completed-parse counter — exists for the debounce acceptance test.
    public private(set) var completedParseCount: Int = 0

    private let engine: any ParseExecuting
    private var options: MarkdownParseOptions
    private let debounce: Duration
    private var pendingTask: Task<Void, Never>?
    private var pendingGeneration: Int = 0
    private var nextRevision: Int = 1
    private var lastText: String = ""

    /// `debounce` is injectable so tests run fast; production uses the default.
    public init(
        engine: any ParseExecuting = ParseEngine(),
        options: MarkdownParseOptions = .default,
        debounce: Duration = .milliseconds(150)
    ) {
        self.engine = engine
        self.options = options
        self.debounce = debounce
    }

    /// Debounced: cancels any pending parse and schedules a new one after
    /// `debounce`. Coalesces rapid keystrokes into ≤ 2 parses (acceptance).
    public func textDidChange(_ text: String) {
        lastText = text
        isParsing = true
        pendingTask?.cancel()

        let generation = pendingGeneration
        pendingGeneration += 1

        let revision = nextRevision
        nextRevision += 1

        pendingTask = Task<Void, Never> { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: debounce)
            } catch is CancellationError {
                clearIfCurrent(generation: generation)
                return
            } catch {
                clearIfCurrent(generation: generation)
                return
            }
            await parse(text: text, revision: revision)
            clearIfCurrent(generation: generation)
        }
    }

    /// Immediate parse, bypassing the debounce (document open, tests).
    /// Cancels any pending debounced parse first. Publishes AND returns.
    @discardableResult
    public func parseNow(_ text: String) async -> MarkdownDocument? {
        lastText = text
        pendingTask?.cancel()
        pendingTask = nil
        let revision = nextRevision
        nextRevision += 1
        return await parse(text: text, revision: revision)
    }

    /// Cancels any pending/running parse without publishing.
    public func cancelPending() {
        pendingTask?.cancel()
        pendingTask = nil
        isParsing = false
        pendingGeneration += 1
    }

    /// Reparse the last text with new options (E13 will call this; tests now).
    public func setOptions(_ options: MarkdownParseOptions) {
        self.options = options
        textDidChange(lastText)
    }

    @discardableResult
    private func parse(text: String, revision: Int) async -> MarkdownDocument? {
        isParsing = true
        defer { isParsing = pendingTask != nil }

        do {
            let result = try await engine.parse(text, options: options, revision: revision)
            guard result.revision > (document?.revision ?? 0) else {
                return nil
            }
            document = result
            completedParseCount += 1
            return result
        } catch is CancellationError {
            return nil
        } catch {
            os_log("Markdown parse failed: %{public}@", error.localizedDescription)
            return nil
        }
    }

    private func clearIfCurrent(generation: Int) {
        guard pendingGeneration == generation else { return }
        pendingTask = nil
        isParsing = false
    }
}
