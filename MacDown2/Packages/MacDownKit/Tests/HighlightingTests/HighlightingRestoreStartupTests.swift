import AppKit
@testable import Highlighting
import Testing

/// Covers edits arriving after a reduced editor attaches Neon but before its initial styling pass.
@MainActor
@Suite(.serialized)
struct HighlightingRestoreStartupTests {
    @Test func severalEditsAtRestoreStartupMatchAFreshHighlighter() async {
        let editor = SizeFallbackFixtures.editor(units: SizeFallbackFixtures.policy.reduceAboveUTF16Units + 500)
        let sleeper = ManualRestoreSleeper()
        editor.highlighter.restoreSleep = sleeper.sleepClosure
        var styledAtTransition: Int?
        editor.highlighter.onStateChange = { [weak editor] state in
            guard let editor, state.mode == .full else { return }
            styledAtTransition = editor.highlighter.styledTokenCount
            editor.insert("x", at: 50)
            editor.insert("y", at: 60)
            editor.paste("", over: NSRange(location: 80, length: 1))
        }
        let toDelete = editor.length - SizeFallbackFixtures.policy.restoreAtOrBelowUTF16Units
        editor.paste("", over: NSRange(location: 100, length: toDelete))
        guard let id = await sleeper.waitForAllocation(after: 0),
              await sleeper.waitForRegistration(id),
              let restore = editor.highlighter.restoreTask
        else {
            Issue.record("idle restore did not register a controlled waiter")
            await sleeper.terminateAndDrain(editor.highlighter.restoreTask.map { [$0] } ?? [])
            return
        }
        #expect(sleeper.advance(by: SizeFallbackFixtures.policy.restoreIdleDelay) == [id])
        await restore.value
        #expect(styledAtTransition == 0)
        #expect(editor.mode == .full)
        #expect(editor.highlighter.gate.forwardedCharacterEditCount == 3)
        #expect(await editor.waitUntilQuiet(quietPeriod: .milliseconds(500)))
        let fresh = HighlightedEditor(text: editor.textView.string, sizePolicy: SizeFallbackFixtures.markdownOnly)
        #expect(await fresh.waitUntilQuiet(quietPeriod: .milliseconds(500)))
        #expect(editor.renderedRuns() == fresh.renderedRuns())
        await sleeper.terminateAndDrain([restore])
    }

    @Test func editingImmediatelyWhenIdleRestoreBecomesFullMatchesAFreshHighlighter() async {
        let editor = SizeFallbackFixtures.editor(units: SizeFallbackFixtures.policy.reduceAboveUTF16Units + 500)
        let sleeper = ManualRestoreSleeper()
        editor.highlighter.restoreSleep = sleeper.sleepClosure
        var styledAtTransition: Int?
        editor.highlighter.onStateChange = { [weak editor] state in
            guard let editor, state.mode == .full else { return }
            styledAtTransition = editor.highlighter.styledTokenCount
            editor.insert("x", at: 50)
        }
        let toDelete = editor.length - SizeFallbackFixtures.policy.restoreAtOrBelowUTF16Units
        editor.paste("", over: NSRange(location: 100, length: toDelete))
        guard let id = await sleeper.waitForAllocation(after: 0),
              await sleeper.waitForRegistration(id),
              let restore = editor.highlighter.restoreTask
        else {
            Issue.record("idle restore did not register a controlled waiter")
            await sleeper.terminateAndDrain(editor.highlighter.restoreTask.map { [$0] } ?? [])
            return
        }

        #expect(sleeper.advance(by: SizeFallbackFixtures.policy.restoreIdleDelay) == [id])
        await restore.value
        #expect(styledAtTransition == 0)
        #expect(editor.mode == .full)
        #expect(editor.highlighter.gate.forwardedCharacterEditCount == 1)
        #expect(await editor.waitUntilQuiet(quietPeriod: .milliseconds(500)))
        let fresh = HighlightedEditor(text: editor.textView.string, sizePolicy: SizeFallbackFixtures.markdownOnly)
        #expect(await fresh.waitUntilQuiet(quietPeriod: .milliseconds(500)))
        #expect(editor.renderedRuns() == fresh.renderedRuns())
        await sleeper.terminateAndDrain([restore])
    }
}
