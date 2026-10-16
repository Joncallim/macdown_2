import AppKit
@testable import Highlighting

/// Small cut-offs so the size fallback can be exercised quickly in Debug; the
/// shipped Markdown cut-off is measured separately in Release
/// (`HighlightBudgetBenchmarkTests`).
enum SizeFallbackFixtures {
    static let policy = HighlightingSizePolicy(
        reduceAboveUTF16Units: 6000,
        restoreAtOrBelowUTF16Units: 4500,
        restoreIdleDelay: .milliseconds(200)
    )

    static func markdownOnly(_ languageID: String?) -> HighlightingSizePolicy? {
        languageID == "markdown" ? policy : nil
    }

    /// Markdown (headings, inline markup, lists, fences) of exactly `units`
    /// UTF-16 code units.
    static func markdown(units: Int) -> String {
        let text = StallFixtures.markdown(utf8Bytes: units + 512)
        return (text as NSString).substring(to: units)
    }

    @MainActor
    static func editor(units: Int) -> HighlightedEditor {
        HighlightedEditor(text: markdown(units: units), sizePolicy: markdownOnly)
    }
}

/// Stands in for Neon's storage delegate behind the gate and records which
/// character edits reached it, forwarding them so Neon keeps working.
final class RecordingStorageDelegate: NSObject, NSTextStorageDelegate {
    private weak var downstream: NSTextStorageDelegate?
    private(set) var willCount = 0
    private(set) var didCount = 0

    init(downstream: NSTextStorageDelegate) {
        self.downstream = downstream
    }

    func textStorage(
        _ textStorage: NSTextStorage,
        willProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        if editedMask.contains(.editedCharacters) {
            willCount += 1
        }
        downstream?.textStorage?(textStorage, willProcessEditing: editedMask, range: editedRange, changeInLength: delta)
    }

    func textStorage(
        _ textStorage: NSTextStorage,
        didProcessEditing editedMask: NSTextStorageEditActions,
        range editedRange: NSRange,
        changeInLength delta: Int
    ) {
        if editedMask.contains(.editedCharacters) {
            didCount += 1
        }
        downstream?.textStorage?(textStorage, didProcessEditing: editedMask, range: editedRange, changeInLength: delta)
    }
}

extension HighlightedEditor {
    var mode: HighlightingState.Mode {
        highlighter.state.mode
    }

    var neonIsAttached: Bool {
        highlighter.highlighter != nil
    }

    var storage: NSTextStorage {
        textView.textStorage ?? NSTextStorage()
    }

    /// No highlighter-owned rendering attribute anywhere: plain presentation.
    var isPlain: Bool {
        renderedRuns().isEmpty
    }

    /// Lets queued main-queue work (deferred presentation clearing, Neon's
    /// `endBuffering`) and short tasks run.
    func settle(_ duration: Duration = .milliseconds(150)) async {
        try? await Task.sleep(for: duration)
    }

    /// Replaces `range` as a paste does, then closes the undo group.
    func paste(_ text: String, over range: NSRange) {
        textView.insertText(text, replacementRange: range)
        textView.breakUndoCoalescing()
    }

    func insert(_ text: String, at location: Int) {
        paste(text, over: NSRange(location: location, length: 0))
    }

    var length: Int {
        (textView.string as NSString).length
    }
}

extension HighlightingState.Mode {
    static let reducedForTestPolicy = HighlightingState.Mode.reduced(
        .documentTooLarge(limitUTF16Units: SizeFallbackFixtures.policy.reduceAboveUTF16Units)
    )
}
