import AppKit

/// Programmatic trigger for the stock `NSTextFinder`.
///
/// The standard Find menu items (⌘F, ⌘G, ⌘⇧F) work automatically through the
/// responder chain because `NSTextView` implements `performTextFinderAction:`.
/// This wrapper exists for non-menu callers (e.g., toolbar buttons) that need
/// to show or hide the find interface directly.
@MainActor
public final class EditorFind {
    private weak var textView: NSTextView?

    /// Configures the text finder for `textView`.
    public init(textView: NSTextView) {
        self.textView = textView
    }

    /// Shows the find bar and focuses the find field.
    public func showFind() {
        perform(.showFindInterface)
    }

    /// Shows the find-and-replace bar.
    public func showReplace() {
        perform(.showReplaceInterface)
    }

    /// Hides the find bar.
    public func hide() {
        perform(.hideFindInterface)
    }

    private func perform(_ action: NSTextFinder.Action) {
        let sender = ActionSender(action: action)
        textView?.performTextFinderAction(sender)
    }
}

/// A minimal object whose `tag` carries the `NSTextFinder.Action`. AppKit reads
/// the sender's tag in `-performTextFinderAction:`.
private final class ActionSender: NSObject {
    var tag: Int

    init(action: NSTextFinder.Action) {
        tag = action.rawValue
        super.init()
    }
}
