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

    @Test func shrinkingBelowTheRestoreThresholdRestoresOnlyAfterIdle() async {
        let editor = Fixtures.editor(units: cutoff + 500)
        let toDelete = editor.length - Fixtures.policy.restoreAtOrBelowUTF16Units
        editor.paste("", over: NSRange(location: 100, length: toDelete))
        #expect(editor.mode == .reducedForTestPolicy)
        // Keep typing: each edit postpones the restore.
        for index in 0 ..< 4 {
            await editor.settle(.milliseconds(100))
            editor.typeOrDelete(at: 50, insert: index.isMultiple(of: 2))
            #expect(editor.mode == .reducedForTestPolicy)
        }
        #expect(await editor.waitUntil { editor.mode == .full }, "restored after the idle delay")
        #expect(await editor.waitUntilQuiet(quietPeriod: .milliseconds(500)))
        let fresh = HighlightedEditor(text: editor.textView.string, sizePolicy: Fixtures.markdownOnly)
        #expect(await fresh.waitUntilQuiet(quietPeriod: .milliseconds(500)))
        #expect(editor.renderedRuns() == fresh.renderedRuns())
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
