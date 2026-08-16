import Foundation
@testable import JSONSupport
import Testing

/// EPIC-11 §3.3/§3.4 — per-document analysis session: debounce coalescing,
/// latest-request-wins publication, cancellation, and off-main computation.
@MainActor
@Suite("JSONAnalysisSession")
struct JSONAnalysisSessionTests {
    /// Waits (bounded) until the session stops analyzing. Fixed sleeps make
    /// these assertions load-sensitive on virtualized CI runners, where
    /// `ContinuousClock` sleeps can stretch and `.utility` detached tasks can
    /// be starved; polling keeps the assertions intact without a timing
    /// budget.
    private func waitUntilIdle(
        _ session: JSONAnalysisSession,
        timeout: Duration = .seconds(2)
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while session.isAnalyzing, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(25))
        }
    }

    @Test func immediateAnalysisOfValidJSONPublishesItems() async {
        let session = JSONAnalysisSession(debounce: .milliseconds(1))
        let result = await session.analyzeNow(#"{"a":1}"#)
        #expect(result.isValid)
        #expect(result.diagnostic == nil)
        #expect(result.outlineItems.first?.id == "$")
        #expect(result.outlineItems.first?.children.first?.id == "$.a")
        #expect(session.result?.text == #"{"a":1}"#)
    }

    @Test func immediateAnalysisOfInvalidJSONPublishesDiagnostic() async {
        let session = JSONAnalysisSession(debounce: .milliseconds(1))
        let result = await session.analyzeNow("{\"a\":\"")
        #expect(!result.isValid)
        #expect(result.diagnostic != nil)
        #expect(result.outlineItems.isEmpty)
        #expect(session.result?.diagnostic?.message.contains("Unterminated string") == true)
    }

    @Test func rapidTextChangesCoalesceAndPublishOnlyLatest() async throws {
        let session = JSONAnalysisSession(debounce: .milliseconds(20))
        session.textDidChange("{\"a\": 1}")
        session.textDidChange("{\"a\": 2}")
        session.textDidChange("{\"a\": 3}")
        try await waitUntilIdle(session)
        // The intermediate invalid states never publish: only the latest text.
        #expect(session.result?.text == "{\"a\": 3}")
        #expect(session.result?.isValid == true)
        #expect(session.completedAnalysisCount == 1)
        #expect(session.isAnalyzing == false)
    }

    @Test func validToInvalidToValidPublishesOnlyLatest() async throws {
        let session = JSONAnalysisSession(debounce: .milliseconds(20))
        session.textDidChange("{\"a\": 1}")
        try await waitUntilIdle(session)
        #expect(session.result?.isValid == true)

        // A valid→invalid→valid burst: the invalid intermediate state never
        // replaces the last published outline.
        session.textDidChange("not json")
        session.textDidChange("{\"a\": 2}")
        try await waitUntilIdle(session)
        #expect(session.result?.text == "{\"a\": 2}")
        #expect(session.result?.isValid == true)
        #expect(session.result?.diagnostic == nil)
        #expect(session.result?.outlineItems.first?.children.first?.id == "$.a")
    }

    @Test func cancelPendingDiscardsWithoutPublishing() async throws {
        let session = JSONAnalysisSession(debounce: .milliseconds(20))
        session.textDidChange("{\"a\": 1}")
        session.cancelPending()
        try await waitUntilIdle(session)
        #expect(session.result == nil)
        #expect(session.isAnalyzing == false)
        #expect(session.completedAnalysisCount == 0)
    }

    @Test func textDidChangeThenAnalyzeNowCancelsTheDebounce() async throws {
        let session = JSONAnalysisSession(debounce: .milliseconds(60))
        session.textDidChange("stale")
        let result = await session.analyzeNow("42")
        #expect(result.isValid)
        try await waitUntilIdle(session)
        // The stale debounced analysis was cancelled; the latest result wins.
        #expect(session.result?.text == "42")
        #expect(session.completedAnalysisCount == 1)
    }

    @Test func isAnalyzingTracksPendingWork() async throws {
        let session = JSONAnalysisSession(debounce: .milliseconds(20))
        #expect(!session.isAnalyzing)
        session.textDidChange("{\"a\": 1}")
        #expect(session.isAnalyzing)
        try await waitUntilIdle(session)
        #expect(!session.isAnalyzing)
    }

    @MainActor
    @Test func storeCachesPerIdentity() {
        let store = JSONAnalysisStore(debounce: .milliseconds(1))
        let first = store.session(for: "tab-1")
        let second = store.session(for: "tab-1")
        #expect(first === second)
        #expect(store.existingSession(for: "tab-1") === first)
        #expect(store.existingSession(for: "tab-2") == nil)
        store.evict("tab-1")
        #expect(store.existingSession(for: "tab-1") == nil)
        #expect(store.session(for: "tab-1") !== first)
    }
}

/// EPIC-11 §3.5 — stale-generation rejection: a formatting result is applied
/// only when the document and editor still match the command-time baseline.
@Suite("JSONFormattingGenerationRace")
struct JSONFormattingGenerationRaceTests {
    private func makeBaseline() -> JSONFormattingBaseline {
        JSONFormattingBaseline(
            text: #"{"a":1}"#,
            documentGeneration: 7,
            editorContentRevision: 42,
            options: JSONFormatOptions(sortKeys: false)
        )
    }

    @Test func acceptsUnchangedBaseline() {
        let baseline = makeBaseline()
        #expect(baseline.accepts(text: #"{"a":1}"#, documentGeneration: 7, editorContentRevision: 42))
    }

    @Test func rejectsWhenTextChangedDuringFormatting() {
        let baseline = makeBaseline()
        // A keystroke landed while the formatting computation was running.
        #expect(!baseline.accepts(text: #"{"a":12}"#, documentGeneration: 7, editorContentRevision: 42))
    }

    @Test func rejectsAfterDocumentGenerationChanged() {
        let baseline = makeBaseline()
        // An external reconcile or save transitioned the document state.
        #expect(!baseline.accepts(text: #"{"a":1}"#, documentGeneration: 8, editorContentRevision: 42))
    }

    @Test func rejectsAfterEditorContentRevisionChanged() {
        let baseline = makeBaseline()
        // The editor observed an edit — even one restoring identical text
        // (e.g. a newline-only edit) — while formatting ran.
        #expect(!baseline.accepts(text: #"{"a":1}"#, documentGeneration: 7, editorContentRevision: 43))
    }

    @Test func identicalTextAfterExternalReloadStillRejects() {
        let baseline = makeBaseline()
        // An external reload replaced the bytes with identical content: the
        // document generation advanced even though the text is unchanged.
        #expect(!baseline.accepts(text: #"{"a":1}"#, documentGeneration: 9, editorContentRevision: 42))
    }

    @Test func optionsArePartOfTheBaseline() {
        let baseline = makeBaseline()
        let sorted = JSONFormattingBaseline(
            text: baseline.text,
            documentGeneration: baseline.documentGeneration,
            editorContentRevision: baseline.editorContentRevision,
            options: JSONFormatOptions(sortKeys: true)
        )
        #expect(sorted.options.sortKeys)
        #expect(sorted != baseline)
        #expect(sorted.accepts(text: baseline.text, documentGeneration: 7, editorContentRevision: 42))
    }
}
