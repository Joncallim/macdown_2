import AppKit
import EditorCore
@testable import Highlighting
import Testing
import Themes

/// Register row H5: work a highlighter queued *before* the cut-off was crossed.
///
/// Neon cannot cancel it, and its validator never goes stale (the content
/// version is the storage's identity hash), so one validation batch of the
/// discarded highlighter still runs on the main actor after reduced mode
/// begins. What these tests establish deterministically (no timing): that batch
/// is *inert* — it styles nothing, builds no live layer, and leaves a plain
/// document — and that nothing new is queued afterwards. Its main-thread cost
/// (about 25 ms extra in Release; 135–210 ms in
/// Debug) is measured in `planning/downstream/evidence/h5-highlight-fallback`
/// and is a known, bounded limitation, not a guarantee of zero stall.
@MainActor
@Suite(.serialized)
struct StaleWorkAfterCrossingTests {
    private typealias Fixtures = SizeFallbackFixtures
    private let cutoff = SizeFallbackFixtures.policy.reduceAboveUTF16Units

    /// Runs the main loop for `duration`, returning the longest scheduling gap
    /// beyond the 5 ms tick (a main-thread stall indicator).
    private func drain(_ duration: Duration) async -> Double {
        let clock = ContinuousClock()
        let end = clock.now + duration
        var last = clock.now
        var worst = 0.0
        while clock.now < end {
            try? await Task.sleep(for: .milliseconds(5))
            let now = clock.now
            let gap = (now - last).components
            let elapsed = Double(gap.seconds) * 1000 + Double(gap.attoseconds) / 1e15 - 5
            worst = max(worst, elapsed)
            last = now
        }
        return worst
    }

    private func make(units: Int) -> (EditorTextSystem, NeonSyntaxHighlighter) {
        let system = EditorTextSystem(
            identity: "stale-\(units)",
            initialText: Fixtures.markdown(units: units),
            configuration: .default
        )
        let highlighter = NeonSyntaxHighlighter(
            textSystem: system, languageID: "markdown", theme: BundledThemes.light,
            registry: GrammarRegistry(), sizePolicy: Fixtures.markdownOnly
        )
        return (system, highlighter)
    }

    private func expectInert(
        _ highlighter: NeonSyntaxHighlighter,
        _ system: EditorTextSystem,
        live: Int,
        styled: Int
    ) async {
        _ = await drain(.seconds(2))
        #expect(highlighter.liveLayerRequestCount == live, "no live parse/layer work after reduced mode began")
        #expect(highlighter.styledTokenCount == styled, "the discarded highlighter styled nothing")
        #expect(HighlightedEditorProbe(textView: system.textView).isPlain)
    }

    @Test func openAndImmediatelyCross() async {
        let (system, highlighter) = make(units: cutoff - 100)
        system.textView.insertText(Fixtures.markdown(units: 200_000), replacementRange: NSRange(location: 0, length: 0))
        #expect(highlighter.state.isReduced)
        await expectInert(
            highlighter,
            system,
            live: highlighter.liveLayerRequestCount,
            styled: highlighter.styledTokenCount
        )
        #expect(
            highlighter.staleLayerRequestCount + highlighter.staleStyleRequestCount > 0,
            "the scenario really left queued work behind"
        )
        highlighter.tearDown()
    }

    @Test func aBackgroundSizedEditThenACrossingPasteInTheSameTurn() async {
        let (system, highlighter) = make(units: cutoff - 3000)
        _ = await drain(.milliseconds(800))
        // 2,100 units: over Neon's 2,048 synchronous limit, so a background reparse starts.
        system.textView.insertText(Fixtures.markdown(units: 2100), replacementRange: NSRange(location: 10, length: 0))
        system.textView.insertText(Fixtures.markdown(units: 400_000), replacementRange: NSRange(location: 0, length: 0))
        #expect(highlighter.state.isReduced)
        await expectInert(
            highlighter,
            system,
            live: highlighter.liveLayerRequestCount,
            styled: highlighter.styledTokenCount
        )
        highlighter.tearDown()
    }

    @Test func undoRedoAcrossTheCutoffRestoresOnlyAfterAnIdleStretch() async {
        let (system, highlighter) = make(units: cutoff - 2500)
        system.textView.insertText(Fixtures.markdown(units: 20000), replacementRange: NSRange(location: 0, length: 0))
        system.textView.breakUndoCoalescing()
        #expect(highlighter.state.isReduced)
        system.undoManager.undo()
        system.undoManager.redo()
        #expect(highlighter.state.isReduced, "redo re-crossed before the idle delay: nothing was restored")
        system.undoManager.undo()
        #expect(highlighter.state.isReduced, "below the restore threshold, but not yet idle")
        for _ in 0 ..< 300 where highlighter.state.mode != .full {
            _ = await drain(.milliseconds(50))
        }
        #expect(highlighter.state.mode == .full, "idle below the restore threshold restores")
        highlighter.tearDown()
    }

    @Test func closingRightAfterTheCrossingLeavesNothingBehind() async {
        let (system, highlighter) = make(units: cutoff - 100)
        system.textView.insertText(Fixtures.markdown(units: 100_000), replacementRange: NSRange(location: 0, length: 0))
        highlighter.tearDown()
        await expectInert(
            highlighter,
            system,
            live: highlighter.liveLayerRequestCount,
            styled: highlighter.styledTokenCount
        )
        #expect(system.textView.textStorage?.delegate == nil)
    }

    @Test func aQuietDocumentGivesTheDiscardedHighlighterNothingToDo() async {
        let (system, highlighter) = make(units: cutoff - 100)
        _ = await drain(.seconds(2))
        system.textView.insertText(Fixtures.markdown(units: 200_000), replacementRange: NSRange(location: 0, length: 0))
        await expectInert(
            highlighter,
            system,
            live: highlighter.liveLayerRequestCount,
            styled: highlighter.styledTokenCount
        )
        #expect(highlighter.staleStyleRequestCount == 0, "control: nothing was queued, so nothing survives")
        highlighter.tearDown()
    }

    @Test func aStaleGenerationIsRefusedAndCountedFromAnyThread() async {
        let state = LayerRequestState()
        state.generation = 3
        #expect(state.note(builtGeneration: 3))
        #expect(!state.note(builtGeneration: 2))
        await withTaskGroup(of: Void.self) { group in
            for index in 0 ..< 8 {
                group.addTask {
                    for _ in 0 ..< 1000 {
                        _ = state.note(builtGeneration: index.isMultiple(of: 2) ? 3 : 2)
                    }
                }
            }
        }
        #expect(state.liveCount == 1 + 4000)
        #expect(state.staleCount == 1 + 4000)
    }
}
