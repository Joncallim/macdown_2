import AppKit
import Foundation

/// Owns exactly one document's live TextKit 2 text system.
///
/// This is a reference type isolated to `@MainActor` because every underlying
/// AppKit object is main-thread only. The store (``EditorTextSystemStore``)
/// caches one system per tab identity so undo history, selection, and scroll
/// position survive tab switches without recreating the text view.
@MainActor
public final class EditorTextSystem {
    /// The stable identity this system is cached under (typically a tab UUID).
    public let identity: String

    /// The text view presented to the user.
    public var textView: NSTextView {
        stack.textView
    }

    /// The content storage that holds the attributed string. E05's highlighter
    /// attaches here.
    public var contentStorage: NSTextContentStorage {
        stack.contentStorage
    }

    /// The layout manager that performs viewport-lazy layout. E05's highlighter
    /// may also attach here.
    public var layoutManager: NSTextLayoutManager {
        stack.layoutManager
    }

    /// Per-tab undo manager. Independent from other tabs.
    public var undoManager: UndoManager {
        textView.undoManager ?? fallbackUndoManager
    }

    private let stack: TextKitStack
    private let fallbackUndoManager = UndoManager()
    private var lastAppliedConfiguration: EditorConfiguration?
    private var lastAppliedOverscroll: OverscrollState?

    /// Snapshot of the inputs that produced the current overscroll inset so we
    /// can skip redundant updates.
    private struct OverscrollState: Equatable {
        let enabled: Bool
        let height: CGFloat
        let textInsets: NSSize
    }

    /// The scroll view that owns the text view. Weak because the scroll view
    /// (via its document view) already strongly references the text view, and
    /// the store strongly references this system.
    weak var scrollView: NSScrollView?

    /// Creates a text system for `identity` with the given initial text and
    /// configuration. The caller should cache the result and reuse it across
    /// view lifecycles.
    public init(identity: String, initialText: String, configuration: EditorConfiguration) {
        self.identity = identity
        stack = TextKitStack()
        apply(configuration)
        setText(initialText)
    }

    // MARK: - Content

    /// Replaces the entire document text. This is intended for external reloads
    /// and conflict resolution; it resets selection and scroll.
    public func setText(_ text: String) {
        textView.string = text
    }

    /// The current plain-text content of the editor.
    public var text: String {
        textView.string
    }

    // MARK: - Configuration

    /// Applies editor preferences to the underlying text view and text container.
    public func apply(_ configuration: EditorConfiguration) {
        let configurationChanged = configuration != lastAppliedConfiguration
        if configurationChanged {
            lastAppliedConfiguration = configuration

            textView.font = configuration.font
            textView.textContainerInset = configuration.textInsets

            // Plain-text editing: Markdown source must not be silently mutated by
            // smart substitutions or rich-text parsing. These are applied here so
            // they stay reactive if a future preference toggle changes them.
            textView.isRichText = false
            textView.smartInsertDeleteEnabled = false
            textView.isAutomaticQuoteSubstitutionEnabled = false
            textView.isAutomaticDashSubstitutionEnabled = false
            textView.isAutomaticTextReplacementEnabled = false

            // Word wrap: when wrapping, the container tracks the clip view width.
            // When not wrapping, the container is given a very large width and the
            // text view is allowed to resize horizontally.
            stack.textContainer.widthTracksTextView = configuration.wrapsLines
            stack.textContainer.heightTracksTextView = false
            if configuration.wrapsLines {
                stack.textContainer.containerSize = NSSize(
                    width: textView.frame.width,
                    height: CGFloat.greatestFiniteMagnitude
                )
                textView.isHorizontallyResizable = false
                textView.autoresizingMask = [.width]
            } else {
                stack.textContainer.containerSize = NSSize(
                    width: CGFloat.greatestFiniteMagnitude,
                    height: CGFloat.greatestFiniteMagnitude
                )
                textView.isHorizontallyResizable = true
                textView.autoresizingMask = [.height]
            }

            // Line height applied as the base typing attribute. This is a base
            // layer; E05's highlighter can layer additional attributes on top.
            let paragraphStyle = NSParagraphStyle.default.mutableCopy() as? NSMutableParagraphStyle
            paragraphStyle?.lineHeightMultiple = configuration.lineHeightMultiple
            if let paragraphStyle {
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: configuration.font,
                    .paragraphStyle: paragraphStyle,
                ]
                textView.typingAttributes = attributes
            }
        }

        // Always apply overscroll, even when the configuration hasn't changed.
        // The correct padding depends on the scroll view's frame, which is not
        // known when the text system is first created (either here or in
        // `EditorView.makeNSView`). Re-applying is cheap because it de-duplicates
        // by the current frame height and enabled flag.
        applyOverscroll(configuration.scrollsPastEnd)
    }

    private func applyOverscroll(_ enabled: Bool) {
        guard let scrollView else { return }
        let height = scrollView.frame.height
        let textInsets = lastAppliedConfiguration?.textInsets ?? .zero
        let current = OverscrollState(enabled: enabled, height: height, textInsets: textInsets)
        if let lastAppliedOverscroll, lastAppliedOverscroll == current {
            return
        }
        lastAppliedOverscroll = current

        let overscrollHeight: CGFloat = enabled ? height : 0
        // Add a bottom content inset so the last line can scroll to the top.
        textView.textContainerInset = NSSize(
            width: textInsets.width,
            height: textInsets.height + overscrollHeight
        )
    }

    // MARK: - Selection / scroll (session restore seam)

    /// The current selected range in UTF-16 offsets.
    public var selectedRange: NSRange {
        get { textView.selectedRange() }
        set { textView.setSelectedRange(newValue) }
    }

    /// The current vertical scroll offset of the clip view.
    public var scrollOffset: CGFloat {
        get { scrollView?.contentView.bounds.origin.y ?? pendingScrollOffset ?? 0 }
        set {
            pendingScrollOffset = newValue
            applyPendingScrollOffset()
        }
    }

    private var pendingScrollOffset: CGFloat?

    /// Applies any pending scroll offset once the text view is inside a scroll
    /// view. Called by ``EditorView`` after mounting the text view.
    func applyPendingScrollOffset() {
        guard let scrollView, let offset = pendingScrollOffset else { return }
        var origin = scrollView.contentView.bounds.origin
        origin.y = offset
        scrollView.contentView.scroll(to: origin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        pendingScrollOffset = nil
    }

    // MARK: - Teardown

    /// Breaks internal references so the text system can deallocate.
    ///
    /// Call this before evicting the system from the cache. It severs the
    /// text-view delegate and breaks the layout graph held by the stack.
    func prepareForDeallocation() {
        textView.delegate = nil
        stack.layoutManager.textContainer = nil
    }
}
