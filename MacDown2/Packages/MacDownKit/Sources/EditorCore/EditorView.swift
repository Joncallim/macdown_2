import AppKit
import SwiftUI

/// A SwiftUI representable that wraps a TextKit 2-backed `NSTextView`.
///
/// The view uses a cached ``EditorTextSystem`` keyed by `identity` so that the
/// underlying text view, undo manager, selection, and scroll position persist
/// across SwiftUI rebuilds (e.g., tab switches).
public struct EditorView: NSViewRepresentable {
    @Binding private var text: String
    private let identity: String
    private let configuration: EditorConfiguration
    private let store: EditorTextSystemStore
    private let onSelectionChange: ((NSRange) -> Void)?
    private let onScrollChange: ((Int) -> Void)?

    /// Creates an editor view.
    /// - Parameters:
    ///   - text: Two-way binding to the document text. Writes flow back on
    ///     every editing transaction.
    ///   - identity: A stable identity for the document (typically a tab UUID).
    ///   - configuration: Editor appearance and behavior preferences.
    ///   - store: The cache that owns per-tab text systems.
    ///   - onSelectionChange: Optional callback invoked when the selection changes.
    ///   - onScrollChange: Optional callback invoked with the UTF-16 offset of
    ///     the character at the top of the visible rect whenever the editor
    ///     scrolls (see ``EditorTextSystem/topVisibleUTF16Offset``).
    public init(
        text: Binding<String>,
        identity: String,
        configuration: EditorConfiguration,
        store: EditorTextSystemStore,
        onSelectionChange: ((NSRange) -> Void)? = nil,
        onScrollChange: ((Int) -> Void)? = nil
    ) {
        _text = text
        self.identity = identity
        self.configuration = configuration
        self.store = store
        self.onSelectionChange = onSelectionChange
        self.onScrollChange = onScrollChange
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let system = store.system(
            for: identity,
            initialText: text,
            configuration: configuration
        )

        let scrollView = NSScrollView(frame: .zero)
        scrollView.documentView = system.textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = !configuration.wrapsLines
        scrollView.autohidesScrollers = configuration.wrapsLines
        scrollView.borderType = .noBorder
        system.scrollView = scrollView

        let gutterView = EditorGutterView(scrollView: scrollView, system: system)
        scrollView.verticalRulerView = gutterView
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        context.coordinator.gutterView = gutterView
        // The scroll view has not been laid out yet, so size the text view to
        // its content (with a minimum that matches the scroll view). The
        // vertically-resizable NSTextView will keep this in sync as the text
        // changes, and the initial content height guarantees the scroll knob
        // reflects the full document immediately.
        let width = max(scrollView.bounds.width, 100)
        // Estimate the content height for a correct scroll knob without
        // blocking on an O(n) layout pass. For documents under 100 KB we
        // compute the exact height; for larger documents we use a generous
        // sentinel and let the vertically-resizable NSTextView grow as-needed.
        let height: CGFloat
        if text.utf8.count < 100_000 {
            let font = system.textView.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
            let contentHeight = (text as NSString).boundingRect(
                with: NSSize(width: width, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: font],
                context: nil
            ).height
            height = max(contentHeight, scrollView.bounds.height)
        } else {
            height = max(50000, scrollView.bounds.height)
        }
        system.textView.frame = NSRect(
            origin: .zero,
            size: CGSize(width: width, height: height)
        )
        system.textView.autoresizingMask = [.width]
        system.applyPendingScrollOffset()

        system.textView.delegate = context.coordinator
        context.coordinator.system = system
        context.coordinator.textBinding = $text
        context.coordinator.onSelectionChange = onSelectionChange
        context.coordinator.onScrollChange = onScrollChange

        registerCoordinatorObservers(scrollView: scrollView, coordinator: context.coordinator)

        return scrollView
    }

    /// Observes scroll changes through the clip view's bounds (NSScrollView
    /// always owns a contentView, so the object is non-optional), plus
    /// undo/redo so the gutter can redraw — `EditorTextSystem` itself keeps
    /// `lineIndex` correct across undo/redo (see its
    /// `registerUndoRedoObservers()`); this coordinator only needs to know
    /// when to invalidate the gutter, which lives at this UI layer.
    ///
    /// The undo/redo observers register with `object: nil` (any sender)
    /// rather than `system.undoManager` evaluated here: at this point
    /// (called from `makeNSView`, before SwiftUI has attached the returned
    /// `NSScrollView` to a window) `system.textView.window` is still nil,
    /// so `EditorTextSystem.undoManager` resolves to its temporary
    /// `fallbackUndoManager` — a different object than the real window
    /// undo manager it switches to once actually mounted. An observer
    /// registered against that stale fallback would never see a real
    /// undo/redo notification (this exact bug was already found and fixed
    /// for `EditorTextSystem`'s OWN line-index-correctness observer, in
    /// `EditorTextSystem+LineIndex.swift` — it just hadn't been applied
    /// here too). `Coordinator.undoManagerDidChange(_:)` re-resolves
    /// `system.undoManager` fresh and checks the notification's sender
    /// against it instead.
    private func registerCoordinatorObservers(scrollView: NSScrollView, coordinator: Coordinator) {
        NotificationCenter.default.addObserver(
            coordinator,
            selector: #selector(Coordinator.scrollViewDidScroll(_:)),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        NotificationCenter.default.addObserver(
            coordinator,
            selector: #selector(Coordinator.undoManagerDidChange(_:)),
            name: .NSUndoManagerDidUndoChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            coordinator,
            selector: #selector(Coordinator.undoManagerDidChange(_:)),
            name: .NSUndoManagerDidRedoChange,
            object: nil
        )
    }

    public func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(
            coordinator,
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        NotificationCenter.default.removeObserver(coordinator, name: .NSUndoManagerDidUndoChange, object: nil)
        NotificationCenter.default.removeObserver(coordinator, name: .NSUndoManagerDidRedoChange, object: nil)
        coordinator.system?.textView.delegate = nil
        coordinator.system?.scrollView = nil
        coordinator.gutterView = nil
    }

    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let system = context.coordinator.system else { return }

        // Apply configuration changes (cheap because we diff at the call site
        // via SwiftUI's update cycle, but `apply` is idempotent).
        system.apply(configuration)
        // A font-size preference change affects the gutter's digit width.
        context.coordinator.gutterView?.updateThickness()

        // Only push model text into the view when it differs from the view's
        // current text *and* the change did not originate from the view itself.
        // This prevents the keystroke-echo feedback loop.
        var pushedModelText = false
        if !context.coordinator.isApplyingModelText, system.text != text {
            context.coordinator.isApplyingModelText = true
            system.setText(text)
            context.coordinator.isApplyingModelText = false
            pushedModelText = true

            // A vertically-resizable NSTextView only grows its document-view
            // height when it is told to size to its content. Only call when
            // text was pushed from the model; user keystrokes already update
            // layout through the NSTextView directly.
            system.textView.sizeToFit()
        }

        // Model pushes need a deferred measurement after TextKit has applied
        // the new text. Ordinary keystrokes already schedule a coalesced sync
        // from the text-view delegate; measuring here as well duplicated the
        // full-document layout pass on every binding update.
        if pushedModelText {
            system.scheduleFrameHeightSync()
        }

        scrollView.hasHorizontalScroller = !configuration.wrapsLines
        scrollView.autohidesScrollers = configuration.wrapsLines
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // MARK: - Coordinator

    public final class Coordinator: NSObject, NSTextViewDelegate {
        weak var system: EditorTextSystem?
        weak var gutterView: EditorGutterView?
        var textBinding: Binding<String>?
        var onSelectionChange: ((NSRange) -> Void)?
        var onScrollChange: ((Int) -> Void)?
        var isApplyingModelText = false
        /// Captured in `shouldChangeTextIn` (every edit this delegate
        /// observes, any origin) and consumed in the very next
        /// `textDidChange` — see that method's doc comment for why this
        /// stays correct even across E10's nested edit interception and an
        /// `EditorEditTransaction`'s per-range multi-firing.
        private var pendingLineIndexEdit: (range: NSRange, replacementUTF16Length: Int)?

        /// Unconditionally keeps `system.lineIndex` current with EVERY edit
        /// this coordinator observes, independent of
        /// `isApplyingMultiRangeTransaction`'s SwiftUI-publication
        /// suppression below — an `EditorEditTransaction` with N ranges
        /// fires `textDidChange` N times (verified by
        /// `EditorEditTransactionTests.multiRangeIsOneUndoStepAndOnePublication`,
        /// the reason that suppression exists in the first place), and the
        /// line index must stay correct after every one of them, not just
        /// the transaction's final state.
        public func textDidChange(_: Notification) {
            if let system, let pending = pendingLineIndexEdit {
                system.noteIncrementalEdit(
                    editedRange: pending.range,
                    replacementUTF16Length: pending.replacementUTF16Length
                )
                pendingLineIndexEdit = nil
            }
            // The gutter has no way to know about a text edit on its own
            // (unlike scrolling, which NSRulerView already tracks via its
            // scroll view) — every edit needs an explicit redraw, and
            // `updateThickness()` also covers a line-count digit-width
            // change (e.g. line 9 -> 10, or 99 -> 100).
            gutterView?.updateThickness()

            guard !isApplyingModelText,
                  let system,
                  !system.isPerformingProgrammaticTextUpdate,
                  !system.isApplyingMultiRangeTransaction
            else { return }
            isApplyingModelText = true
            textBinding?.wrappedValue = system.text
            isApplyingModelText = false
            system.noteTextEdit()
            // Typing changes the content height; keep the document view's
            // frame in step so the caret always has somewhere to scroll to.
            system.scheduleFrameHeightSync()
        }

        /// E10 typed-replacement hook. Returns `true` when AppKit should
        /// perform the original edit, `false` when the assist already applied
        /// a replacement (or moved the selection).
        public func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedRange: NSRange,
            replacementString: String?
        ) -> Bool {
            guard let system else { return true }
            guard let replacementString else { return true }
            // Captured before every branch below (including the E10/IME
            // early returns), since AppKit performs exactly
            // (affectedRange, replacementString) as the edit on every path
            // that returns `true` here, and a nested edit that vetoes this
            // one (E10 intercepting it) overwrites this same property with
            // ITS OWN (affectedRange, replacementString) before ITS OWN
            // `textDidChange` consumes it — see that method's doc comment.
            pendingLineIndexEdit = (affectedRange, (replacementString as NSString).length)
            guard !isApplyingModelText else { return true }
            guard !system.isPerformingProgrammaticTextUpdate else { return true }
            guard !system.isPerformingEditingAssist else { return true }
            guard system.editingAssistConfiguration.isEnabled else { return true }

            // IME safety: marked text passes through untouched. A marked
            // range whose location is NSNotFound is never a real range.
            let marked = textView.markedRange()
            if textView.hasMarkedText() ||
                (marked.location != NSNotFound && NSIntersectionRange(marked, affectedRange).length > 0)
            // swiftlint:disable:next opening_brace
            {
                return true
            }

            // Fail open: without the expected live backing source, the editor
            // behaves exactly like native AppKit. Report the architecture
            // event in Debug rather than falling back to an O(document) copy.
            guard let source = system.assistTextSource else {
                assertionFailure("E10: live NSTextStorage backing source unavailable")
                return true
            }

            let outcome = MarkdownEditingAssistEngine.outcome(
                for: .replacement(range: affectedRange, string: replacementString),
                text: source,
                selection: system.selectedRange,
                configuration: system.editingAssistConfiguration
            )
            return !system.applyAssistOutcome(outcome)
        }

        /// E10 command hook. Returns `true` when the command was handled,
        /// `false` when AppKit should continue with the responder chain.
        public func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard let system else { return false }
            guard system.editingAssistConfiguration.isEnabled else { return false }
            guard !isApplyingModelText,
                  !system.isPerformingProgrammaticTextUpdate,
                  !system.isPerformingEditingAssist
            else { return false }
            // Marked text (IME composition) passes through untouched.
            guard !textView.hasMarkedText() else { return false }

            guard let action = Self.editingAssistAction(for: selector) else { return false }
            guard let source = system.assistTextSource else { return false }
            let outcome = MarkdownEditingAssistEngine.outcome(
                for: action,
                text: source,
                selection: system.selectedRange,
                configuration: system.editingAssistConfiguration
            )
            return system.applyAssistOutcome(outcome)
        }

        public func textViewDidChangeSelection(_: Notification) {
            guard let system else { return }
            system.scheduleFrameHeightSync()
            onSelectionChange?(system.selectedRange)
        }

        /// Maps the AppKit text command selectors E10 understands. Everything
        /// else returns `nil` and falls through to native behavior.
        private static func editingAssistAction(for selector: Selector) -> EditingAssistAction? {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                .insertNewline
            case #selector(NSResponder.insertTab(_:)):
                .insertTab
            case #selector(NSResponder.insertBacktab(_:)):
                .insertBacktab
            case #selector(NSResponder.deleteBackward(_:)):
                .deleteBackward
            case #selector(NSResponder.moveToLeftEndOfLine(_:)):
                .smartHome
            default:
                nil
            }
        }

        @objc @MainActor func scrollViewDidScroll(_: Notification) {
            guard let system else { return }
            onScrollChange?(system.topVisibleUTF16Offset)
        }

        /// `EditorTextSystem` itself keeps `lineIndex` correct across
        /// undo/redo (see its own `registerUndoRedoObservers()`); this
        /// coordinator-level observer exists only to redraw the gutter,
        /// which `EditorTextSystem` has no reference to.
        @objc @MainActor func undoManagerDidChange(_ notification: Notification) {
            // Registered with `object: nil` (see `registerCoordinatorObservers`'s
            // doc comment), so this fires for every text system's undo/redo
            // in the app — filter to this one's current (freshly-resolved,
            // not cached) undo manager.
            guard let system, notification.object as AnyObject === system.undoManager else { return }
            gutterView?.updateThickness()
        }
    }
}
