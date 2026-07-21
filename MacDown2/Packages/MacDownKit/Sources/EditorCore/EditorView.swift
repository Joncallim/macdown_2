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
    private let onScrollChange: ((CGFloat) -> Void)?

    /// Creates an editor view.
    /// - Parameters:
    ///   - text: Two-way binding to the document text. Writes flow back on
    ///     every editing transaction.
    ///   - identity: A stable identity for the document (typically a tab UUID).
    ///   - configuration: Editor appearance and behavior preferences.
    ///   - store: The cache that owns per-tab text systems.
    ///   - onSelectionChange: Optional callback invoked when the selection changes.
    ///   - onScrollChange: Optional callback invoked when the scroll offset changes.
    public init(
        text: Binding<String>,
        identity: String,
        configuration: EditorConfiguration,
        store: EditorTextSystemStore,
        onSelectionChange: ((NSRange) -> Void)? = nil,
        onScrollChange: ((CGFloat) -> Void)? = nil
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
        system.textView.frame = scrollView.bounds
        system.textView.autoresizingMask = [.width, .height]
        system.applyPendingScrollOffset()

        system.textView.delegate = context.coordinator
        context.coordinator.system = system
        context.coordinator.textBinding = $text
        context.coordinator.onSelectionChange = onSelectionChange
        context.coordinator.onScrollChange = onScrollChange

        // Observe scroll changes through the clip view's bounds. NSScrollView
        // always owns a contentView, so the object is non-optional.
        let contentView = scrollView.contentView
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.scrollViewDidScroll(_:)),
            name: NSView.boundsDidChangeNotification,
            object: contentView
        )

        return scrollView
    }

    public func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(
            coordinator,
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
        coordinator.system?.textView.delegate = nil
        coordinator.system?.scrollView = nil
    }

    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let system = context.coordinator.system else { return }

        // Apply configuration changes (cheap because we diff at the call site
        // via SwiftUI's update cycle, but `apply` is idempotent).
        system.apply(configuration)

        // Only push model text into the view when it differs from the view's
        // current text *and* the change did not originate from the view itself.
        // This prevents the keystroke-echo feedback loop.
        if !context.coordinator.isApplyingModelText, system.text != text {
            context.coordinator.isApplyingModelText = true
            system.setText(text)
            context.coordinator.isApplyingModelText = false
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
        var textBinding: Binding<String>?
        var onSelectionChange: ((NSRange) -> Void)?
        var onScrollChange: ((CGFloat) -> Void)?
        var isApplyingModelText = false

        public func textDidChange(_: Notification) {
            guard !isApplyingModelText, let system else { return }
            isApplyingModelText = true
            textBinding?.wrappedValue = system.text
            isApplyingModelText = false
        }

        public func textViewDidChangeSelection(_: Notification) {
            guard let system else { return }
            onSelectionChange?(system.selectedRange)
        }

        @objc @MainActor func scrollViewDidScroll(_: Notification) {
            guard let system else { return }
            onScrollChange?(system.scrollOffset)
        }
    }
}
