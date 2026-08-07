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
    private var lastFrameSyncSignature: FrameSyncSignature?
    private var measuredContentHeight: CGFloat = 0
    /// Set by `scrollOffset`'s setter before the scroll view exists yet
    /// (session restore); applied by `applyPendingScrollOffset()` once it does.
    var pendingScrollOffset: CGFloat?

    /// Snapshot of the inputs that produced the current overscroll inset so we
    /// can skip redundant updates.
    private struct OverscrollState: Equatable {
        let enabled: Bool
        let height: CGFloat
        let textInsets: NSSize
    }

    /// Snapshot of the inputs that produced the last frame-height sync, so
    /// `syncFrameHeightToContent()` can skip the (TextKit 2 layout) work when
    /// neither has changed.
    private struct FrameSyncSignature: Equatable {
        let textLength: Int
        let width: CGFloat
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
        // A wholesale text replacement invalidates any measured height from
        // the previous document — see `syncFrameHeightToContent`.
        measuredContentHeight = 0
        lastFrameSyncSignature = nil
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

    /// Corrects the text view's frame height against TextKit 2's real,
    /// laid-out content bounds.
    ///
    /// `isVerticallyResizable = true` does not, on its own, keep this
    /// manually-constructed TextKit 2 stack's frame in sync with content
    /// outside the viewport-lazy layout pass — nothing here ever asks the
    /// layout manager to lay out beyond what has actually been visible, so
    /// the frame stays close to whatever `EditorView.makeNSView`'s initial
    /// (plain `NSString.boundingRect`, and at that point almost certainly the
    /// wrong width — the scroll view has not been laid out yet) estimate
    /// produced. Scrolling — via `scrollRangeToVisible`, keyboard caret
    /// navigation, or manual scroll — has nowhere further to go once the
    /// frame stops growing, which reads as "scrolling doesn't work" even
    /// though the selection/caret genuinely moved.
    ///
    /// Forces one full-document layout pass and applies the real content
    /// height, so this is skipped for documents ≥ 100 KB — the same
    /// threshold `makeNSView` already uses to avoid blocking on an O(n)
    /// layout for large files. Cheap to call on every `updateNSView`: it
    /// no-ops unless the text length or available width actually changed.
    ///
    /// The computed height is re-measured fresh for each distinct (text
    /// length, width) signature — it is NOT accumulated as a running maximum
    /// across signatures. A previous, different width or text length can
    /// genuinely need a *different* height (a narrower container wraps to
    /// more lines; shorter text needs less), so an earlier signature's
    /// height is not a valid floor for a new one. Carrying it forward as one
    /// left the frame stuck too tall after a pane resize or a large
    /// deletion — a permanent blank gap below the actual content.
    func syncFrameHeightToContent() {
        guard let scrollView else { return }
        let string = textView.string as NSString
        guard string.length < 100_000 else { return }

        // Matching text/width does NOT mean the frame still matches the last
        // measurement: TextKit 2's viewport controller reclaims off-screen
        // fragments on its own schedule and has been observed shrinking
        // `textView.frame` between calls with nothing here to invalidate the
        // signature. Skipping the reapplication below left it stuck shrunk,
        // so a later `scrollRangeToVisible` (e.g. the outline's
        // jump-to-heading) clamped against it and landed far from the target.
        let signature = FrameSyncSignature(textLength: string.length, width: textView.frame.width)
        guard signature != lastFrameSyncSignature else {
            applyMeasuredFrameHeight(scrollView: scrollView)
            return
        }
        lastFrameSyncSignature = signature

        // `usageBoundsForTextContainer` does not reflect a forced
        // `ensureLayout(for:)` pass for this manually-constructed stack —
        // measured directly, it stayed pinned near the viewport height
        // regardless. Enumerating fragments with `.ensuresLayout` forces
        // each one through real layout and hands back its actual frame,
        // which is the approach Apple's own TextKit 2 sample code uses to
        // compute total content height.
        var maxY: CGFloat = 0
        _ = layoutManager.enumerateTextLayoutFragments(
            from: layoutManager.documentRange.location,
            options: [.ensuresLayout]
        ) { fragment in
            maxY = max(maxY, fragment.layoutFragmentFrame.maxY)
            return true
        }
        measuredContentHeight = maxY
        applyMeasuredFrameHeight(scrollView: scrollView)
    }

    /// Syncs `textView.frame.height` to exactly what `measuredContentHeight`
    /// (for the current signature) requires — growing OR shrinking it, since
    /// both a stale-small frame (TextKit 2 shrank it behind our back) and a
    /// stale-large one (carried over from a since-resized/edited signature)
    /// are equally wrong.
    private func applyMeasuredFrameHeight(scrollView: NSScrollView) {
        let neededHeight = max(measuredContentHeight, scrollView.bounds.height)
        if textView.frame.height != neededHeight {
            textView.frame.size.height = neededHeight
        }
    }

    /// Brings the frame height up to date off the back of an editing or
    /// caret-movement event, one run-loop turn later.
    ///
    /// Keyboard-driven caret movement and typing are entirely internal to
    /// `NSTextView` — they never flow through SwiftUI's `updateNSView`, so
    /// `syncFrameHeightToContent()` would otherwise never run for those paths
    /// and the frame would fall behind the content again. Cheap on the common
    /// path: the signature check inside no-ops once the frame has caught up.
    ///
    /// Deferred one run-loop turn because the delegate callbacks that drive
    /// this fire *during* `NSTextView`'s own handling, before it has finished
    /// updating its layout; measuring then reads a half-updated state.
    ///
    /// This deliberately does **not** scroll. An earlier version called
    /// `scrollRangeToVisible(selection)` here, which meant every selection
    /// change — including ones the user never initiated — yanked the viewport
    /// back to the caret, so scrolling away from the caret and releasing
    /// snapped straight back to it. `NSTextView` already scrolls to follow the
    /// caret on its own; all it ever needed from us was a frame tall enough
    /// to have somewhere to scroll to.
    func scheduleFrameHeightSync() {
        Task { @MainActor [weak self] in
            self?.syncFrameHeightToContent()
        }
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
