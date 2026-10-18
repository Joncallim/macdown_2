import AppKit
@testable import Highlighting
import Testing

/// Register row H5: the bounded size-based highlighting fallback — cut-off,
/// interception of the crossing edit before Neon, teardown, hysteresis.
@MainActor
@Suite(.serialized)
struct HighlightingSizeFallbackTests {
    private typealias Fixtures = SizeFallbackFixtures
    private let cutoff = SizeFallbackFixtures.policy.reduceAboveUTF16Units

    // MARK: - Cut-off

    @Test func justBelowAndAtTheCutoffGetFullHighlighting() async {
        for units in [cutoff - 1, cutoff] {
            let editor = Fixtures.editor(units: units)
            #expect(editor.mode == .full)
            #expect(editor.neonIsAttached)
            #expect(editor.highlighter.state.requestedLanguageID == "markdown")
            #expect(await editor.waitUntilQuiet(quietPeriod: .milliseconds(500)))
            #expect(!editor.isPlain)
        }
    }

    @Test func aboveTheCutoffOpensReducedWithoutBuildingAParser() async {
        let editor = Fixtures.editor(units: cutoff + 1)
        #expect(editor.mode == .reducedForTestPolicy)
        #expect(!editor.neonIsAttached)
        #expect(editor.highlighter.generation == 0, "no Neon highlighter was ever built")
        #expect(editor.highlighter.languageID == "markdown", "the requested language is kept")
        editor.insert("x", at: 10)
        await editor.settle()
        #expect(editor.highlighter.gate.forwardedCharacterEditCount == 0)
        #expect(editor.highlighter.styledTokenCount == 0)
        #expect(editor.isPlain)
    }

    /// The cut-off counts UTF-16 code units, never UTF-8 bytes: 2,000 emoji are
    /// 8,000 bytes but 4,000 units (full); CJK is 3 bytes per unit.
    @Test func theCutoffIsInUTF16Units() {
        let emoji = String(repeating: "😀", count: 2000)
        #expect(emoji.utf8.count > cutoff)
        #expect(HighlightedEditor(text: emoji, sizePolicy: Fixtures.markdownOnly).mode == .full)

        let cjk = String(repeating: "漢", count: cutoff)
        #expect(cjk.utf8.count == 3 * cutoff)
        #expect(HighlightedEditor(text: cjk, sizePolicy: Fixtures.markdownOnly).mode == .full)
        let cjkOver = HighlightedEditor(text: cjk, sizePolicy: Fixtures.markdownOnly)
        cjkOver.insert("😀", at: 1) // one emoji = 2 units: crosses
        #expect(cjkOver.mode == .reducedForTestPolicy)
        #expect(cjkOver.length == cutoff + 2)
    }

    // MARK: - Interception before Neon

    /// The proof that the crossing edit is intercepted *before* Neon's
    /// synchronous reparse: Neon learns of edits only through its storage
    /// delegate (willProcessEditing records, didProcessEditing reparses), and
    /// the recording stand-in behind the gate sees neither callback for it.
    @Test func theCrossingEditNeverReachesNeon() async throws {
        let editor = Fixtures.editor(units: cutoff - 1)
        #expect(await editor.waitUntilQuiet(quietPeriod: .milliseconds(500)))
        let spy = try RecordingStorageDelegate(downstream: #require(editor.highlighter.gate.downstream))
        editor.highlighter.gate.downstream = spy

        editor.insert("x", at: 10) // now exactly at the cut-off: still full
        #expect((spy.willCount, spy.didCount) == (1, 1))
        #expect(editor.mode == .full)

        editor.insert("y", at: 10) // crosses
        #expect((spy.willCount, spy.didCount) == (1, 1), "Neon must not hear about the crossing edit")
        #expect(editor.mode == .reducedForTestPolicy)
        #expect(!editor.neonIsAttached)
        #expect(editor.highlighter.gate.characterEditCount == 2)
        #expect(editor.highlighter.gate.forwardedCharacterEditCount == 1)
        #expect(editor.highlighter.gate.downstream == nil)
    }

    @Test func aCrossingPasteIsWithheldAndThePresentationBecomesPlain() async {
        let editor = Fixtures.editor(units: 4000)
        #expect(await editor.waitUntilQuiet(quietPeriod: .milliseconds(500)))
        #expect(!editor.isPlain)
        // An immutable copy: the text view's string is backed by the live storage.
        let before = NSString(string: editor.textView.string)
        let paste = Fixtures.markdown(units: 3000)
        let forwarded = editor.highlighter.gate.forwardedCharacterEditCount

        editor.insert(paste, at: 1234)
        #expect(editor.mode == .reducedForTestPolicy)
        #expect(editor.highlighter.gate.forwardedCharacterEditCount == forwarded)
        #expect(editor.textView.string == before.replacingCharacters(
            in: NSRange(location: 1234, length: 0),
            with: paste
        ))

        let styled = editor.highlighter.styledTokenCount
        await editor.settle(.seconds(1))
        #expect(editor.isPlain, "highlighter-owned colour/font/underline removed")
        #expect(editor.highlighter.styledTokenCount == styled, "no late styling from the discarded highlighter")
    }

    /// Several forwarded edits and the crossing one in one main-actor turn
    /// (e.g. Replace All), then a large shrink in the same turn: the discarded
    /// highlighter's queued work must neither crash (Debug asserts on stale
    /// out-of-range reads) nor style the text.
    @Test func queuedWorkFromTheDiscardedHighlighterIsInert() async {
        let editor = Fixtures.editor(units: 5900)
        for index in 0 ..< 5 {
            editor.textView.insertText("ab", replacementRange: NSRange(location: 100 + index, length: 0))
        }
        editor.textView.insertText(Fixtures.markdown(units: 4000), replacementRange: NSRange(location: 50, length: 0))
        editor.textView.insertText("", replacementRange: NSRange(location: 0, length: 3000))
        #expect(editor.mode == .reducedForTestPolicy)
        let styled = editor.highlighter.styledTokenCount
        await editor.settle(.seconds(2))
        #expect(editor.highlighter.styledTokenCount == styled)
        #expect(editor.isPlain)
    }

    // MARK: - Undo, shrink, hysteresis

    @Test func undoingTheCrossingPasteRestoresFullHighlightingAfterIdle() async {
        let editor = Fixtures.editor(units: 4000)
        #expect(await editor.waitUntilQuiet(quietPeriod: .milliseconds(500)))
        let original = editor.textView.string
        editor.insert(Fixtures.markdown(units: 3000), at: 2000)
        #expect(editor.mode == .reducedForTestPolicy)

        editor.highlighter.textSystem.undoManager.undo()
        #expect(editor.textView.string == original)
        #expect(editor.mode == .reducedForTestPolicy, "no rebuild in the middle of editing")
        #expect(await editor.waitUntil { editor.mode == .full }, "restored after the idle delay")
        #expect(editor.neonIsAttached)

        editor.highlighter.textSystem.undoManager.redo()
        #expect(editor.mode == .reducedForTestPolicy)
        #expect(editor.length == 7000)
    }

    @Test func editingAroundTheCutoffNeverRebuilds() async {
        let editor = Fixtures.editor(units: cutoff + 1)
        for _ in 0 ..< 20 {
            editor.typeOrDelete(at: 10, insert: false) // dips to the cut-off
            editor.typeOrDelete(at: 10, insert: true) // and back over it
        }
        await editor.settle(.milliseconds(600))
        #expect(editor.mode == .reducedForTestPolicy, "above the restore threshold: stays reduced")
        #expect(editor.highlighter.generation == 0, "never rebuilt")
    }

    /// A short pause cannot restore a reduced editor. A real idle period may restore it, after which small edits
    /// keep full highlighting. Measure from before each edit so the measured interval bounds the timer's age.
    @Test(arguments: [false, true])
    func shrinkingBelowTheRestoreThresholdRestoresOnlyAfterIdle(includesIdlePause: Bool) async {
        let editor = Fixtures.editor(units: cutoff + 500)
        let idle = Fixtures.policy.restoreIdleDelay
        let clock = ContinuousClock()
        let toDelete = editor.length - Fixtures.policy.restoreAtOrBelowUTF16Units
        var lastEditStarted = clock.now
        editor.paste("", over: NSRange(location: 100, length: toDelete))
        #expect(editor.mode == .reducedForTestPolicy)
        var checksWhileNotIdle = 0
        var wasReducedAfterLastEdit = true
        var timeline: [String] = []
        // Keep typing: each edit postpones the restore.
        for index in 0 ..< 4 {
            // The third pause follows a deletion to the restore threshold. The second is above it.
            await editor.settle(.milliseconds(includesIdlePause && index == 2 ? 300 : 100))
            if wasReducedAfterLastEdit, clock.now - lastEditStarted < idle {
                checksWhileNotIdle += 1
                #expect(editor.mode == .reducedForTestPolicy, "restored before an idle delay had elapsed")
            }
            timeline.append(
                "pause \(index): elapsed=\(clock.now - lastEditStarted), mode=\(editor.mode), "
                    + "revision=\(editor.system.contentRevision), generation=\(editor.highlighter.generation), "
                    + "tokens=\(editor.highlighter.styledTokenCount)"
            )
            let modeBeforeEdit = editor.mode
            lastEditStarted = clock.now
            editor.typeOrDelete(at: 50, insert: index.isMultiple(of: 2))
            #expect(editor.mode == modeBeforeEdit, "a small edit neither restores nor reduces highlighting")
            wasReducedAfterLastEdit = editor.mode == .reducedForTestPolicy
        }
        // If the runner was so slow that no check ran while not idle, the test proved nothing: say so.
        #expect(checksWhileNotIdle >= 1, "every pause exceeded the idle delay; the early-restore check never ran")
        #expect(await editor.waitUntil { editor.mode == .full }, "restored after the idle delay")
        #expect(await editor.waitUntilQuiet(quietPeriod: .milliseconds(500)))
        let fresh = HighlightedEditor(text: editor.textView.string, sizePolicy: Fixtures.markdownOnly)
        #expect(await fresh.waitUntilQuiet(quietPeriod: .milliseconds(500)))
        let expectedRuns = fresh.renderedRuns()
        let matches = editor.renderedRuns() == expectedRuns
        #expect(editor.renderedRuns() == expectedRuns, "\(timeline.joined(separator: "; "))")
        if !matches {
            // Preserve the failed assertion before observing whether delayed work or an explicit
            // revalidation changes the result. These bounded probes never convert failure to success.
            await editor.settle(.seconds(2))
            reportRestoreStyles("after2s", editor: editor, fresh: fresh, initialReference: expectedRuns)
            editor.highlighter.invalidateAll()
            await editor.settle(.seconds(2))
            reportRestoreStyles("afterInvalidation", editor: editor, fresh: fresh, initialReference: expectedRuns)
            editor.highlighter.setLanguage(nil)
            editor.highlighter.setLanguage("markdown")
            await editor.settle(.seconds(2))
            reportRestoreStyles("afterRebuild", editor: editor, fresh: fresh, initialReference: expectedRuns)
        }
    }

    private func reportRestoreStyles(
        _ stage: String, editor: HighlightedEditor, fresh: HighlightedEditor, initialReference: [RenderedRun]
    ) {
        let currentReference = fresh.renderedRuns()
        let observed = editor.renderedRuns()
        print(
            "RESTORE_STYLE_PROBE \(stage): referenceUnchanged=\(currentReference == initialReference), "
                + "matchesInitial=\(observed == initialReference), matchesCurrent=\(observed == currentReference)"
        )
    }

    /// Below the cut-off the fallback is invisible: typing and deleting a block
    /// match a fresh highlighter (selection replacement is a separately tracked
    /// pre-existing defect, see `NeonReplacementEditTests`).
    @Test func belowTheCutoffHighlightingMatchesAFreshHighlighter() async {
        let editor = Fixtures.editor(units: 5000)
        #expect(await editor.waitUntilQuiet(quietPeriod: .milliseconds(500)))
        for index in 0 ..< 7 {
            editor.typeOrDelete(at: 2500, insert: index.isMultiple(of: 2))
        }
        await editor.settle(.milliseconds(300))
        editor.textView.insertText("", replacementRange: NSRange(location: 1000, length: 800))
        #expect(await editor.waitUntilQuiet(quietPeriod: .seconds(1)))
        let fresh = HighlightedEditor(text: editor.textView.string, sizePolicy: Fixtures.markdownOnly)
        #expect(await fresh.waitUntilQuiet(quietPeriod: .milliseconds(500)))
        #expect(editor.renderedRuns() == fresh.renderedRuns())
        #expect(editor.highlighter.gate.forwardedCharacterEditCount == editor.highlighter.gate.characterEditCount)
    }
}
