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
    private var maxObservedContentHeight: CGFloat = 0

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
        // A wholesale text replacement invalidates any content-height
        // watermark from the previous document — see `syncFrameHeightToContent`.
        maxObservedContentHeight = 0
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
    /// The computed height is applied as a **watermark** — `textView.frame`
    /// only ever grows here, never shrinks. Measured directly: TextKit 2's
    /// viewport layout controller reclaims (invalidates) fragments outside
    /// the currently-visible area as its own housekeeping, so a *later*
    /// enumeration of the same unchanged document can legitimately report a
    /// *smaller* `maxY` than an earlier one did, purely because fewer
    /// fragments happen to be materialized at that instant — not because the
    /// document got shorter. Applying that smaller number directly would
    /// intermittently shrink the frame back to viewport size and reintroduce
    /// the exact bug this method exists to fix.
    func syncFrameHeightToContent() {
        guard let scrollView else { return }
        let string = textView.string as NSString
        guard string.length < 100_000 else { return }

        let signature = FrameSyncSignature(textLength: string.length, width: textView.frame.width)
        guard signature != lastFrameSyncSignature else { return }
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
        maxObservedContentHeight = max(maxObservedContentHeight, maxY)

        let neededHeight = max(maxObservedContentHeight, scrollView.bounds.height)
        if neededHeight > textView.frame.height {
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

    /// The UTF-16 offset of the character at the top-left of the visible rect.
    ///
    /// Returns `0` when the text view has no layout or is not installed in a
    /// scroll view. This is the editor side of the scroll-sync seam.
    public var topVisibleUTF16Offset: Int {
        // Without a scroll view there is no viewport to measure against. An
        // unlaid-out text view answers hit-tests with the end of the document,
        // so return the documented 0 rather than that misleading value.
        guard let scrollView else { return 0 }

        let clipOrigin = scrollView.contentView.bounds.origin
        let point = textView.convert(clipOrigin, from: scrollView.contentView)
        // `characterIndexForInsertion(at:)` takes a point in the text view's own
        // coordinate space. `NSTextInputClient.characterIndex(for:)` looks
        // similar but expects *screen* coordinates, so it silently returns
        // nonsense for a view-local point.
        let index = textView.characterIndexForInsertion(at: point)
        return index == NSNotFound ? 0 : index
    }

    /// Scrolls the given UTF-16 range into the visible rect.
    ///
    /// This is a thin seam over `NSTextView.scrollRangeToVisible(_:)` so the
    /// app target can drive editor scroll from the preview without depending
    /// on AppKit directly.
    ///
    /// Callers build the range from a *parsed* document's `SourceMap`, which
    /// trails the live text by up to one debounce interval. Delete a trailing
    /// section and sync inside that window and the range runs past the end of
    /// the text, so it is clamped here.
    ///
    /// Measured on macOS 26.6, `NSTextView.scrollRangeToVisible(_:)` clamps
    /// such a range internally rather than raising — so this is not a crash
    /// fix, and E08's plan (§2.3) is wrong to describe it as one. It is here
    /// to make the contract explicit and version-independent: a stale range
    /// scrolls to the end of the live text, by this code's decision rather
    /// than by an undocumented AppKit one.
    public func scrollToVisible(utf16Range range: NSRange) {
        syncFrameHeightToContent()
        textView.scrollRangeToVisible(clampedToLiveText(range))
    }

    /// Places the selection at `range`, brings it on screen, and optionally
    /// flashes the native find indicator over it (D9 — the outline's jump).
    ///
    /// `range` is clamped to the live text, for the same reason as
    /// `scrollToVisible` above. Order matters: select → ensure layout for the
    /// range → scroll → flash. `showFindIndicator(for:)` draws from laid-out
    /// geometry, so flashing before layout puts it in the wrong place or
    /// drops it silently. `syncFrameHeightToContent()` runs first so the
    /// frame actually has somewhere to scroll into — see its doc comment.
    public func revealSelection(utf16Range range: NSRange, flash: Bool) {
        syncFrameHeightToContent()
        let clamped = clampedToLiveText(range)
        textView.setSelectedRange(clamped)
        ensureLayout(for: clamped)
        textView.scrollRangeToVisible(clamped)
        if flash {
            textView.showFindIndicator(for: clamped)
        }
    }

    /// Clamps a range built against a stale snapshot to the live text length.
    ///
    /// Uses `NSString.length` — UTF-16 code units, the unit `NSRange` is in.
    /// `String.count` counts Characters and under-clamps on emoji and CJK,
    /// which is exactly where a stale range is most likely to be wrong.
    func clampedToLiveText(_ range: NSRange) -> NSRange {
        let length = (textView.string as NSString).length
        let location = min(max(0, range.location), length)
        let maxLength = length - location
        return NSRange(location: location, length: min(max(0, range.length), maxLength))
    }

    private func ensureLayout(for range: NSRange) {
        let documentStart = contentStorage.documentRange.location
        guard let start = contentStorage.location(documentStart, offsetBy: range.location),
              let end = contentStorage.location(start, offsetBy: range.length),
              let textRange = NSTextRange(location: start, end: end)
        else {
            return
        }
        layoutManager.ensureLayout(for: textRange)
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
