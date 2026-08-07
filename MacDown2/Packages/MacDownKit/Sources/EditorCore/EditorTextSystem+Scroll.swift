import AppKit
import QuartzCore

// MARK: - Selection / scroll (session restore seam)

public extension EditorTextSystem {
    /// The current selected range in UTF-16 offsets.
    var selectedRange: NSRange {
        get { textView.selectedRange() }
        set { textView.setSelectedRange(newValue) }
    }

    /// The current vertical scroll offset of the clip view.
    var scrollOffset: CGFloat {
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
    var topVisibleUTF16Offset: Int {
        // Without a scroll view there is no viewport to measure against.
        guard let scrollView else { return 0 }

        let clipOrigin = scrollView.contentView.bounds.origin
        let point = textView.convert(clipOrigin, from: scrollView.contentView)

        // `NSTextView.characterIndexForInsertion(at:)` (view-local, unlike the
        // similar-looking but screen-space `NSTextInputClient.characterIndex(for:)`)
        // was tried first, but can misreport a point inside a correctly
        // laid-out fragment as past the END of the document — seen right
        // after the outline sidebar's "reveal heading" jump, feeding a bogus
        // near-end offset into scroll-sync and dragging the preview to the
        // bottom while the editor had genuinely landed on target. The layout
        // manager's own fragment lookup at the same point does not share it.
        guard let fragment = layoutManager.textLayoutFragment(for: point) else {
            return 0
        }
        let documentStart = contentStorage.documentRange.location
        return contentStorage.offset(from: documentStart, to: fragment.rangeInElement.location)
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
    func scrollToVisible(utf16Range range: NSRange) {
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
    ///
    /// `animated` drives a short, easing scroll instead of an instant jump —
    /// used by the outline sidebar, where an instant snap read as jarring
    /// for a jump that can span most of the document. It falls back to the
    /// instant `scrollRangeToVisible(_:)` if no scroll view is attached yet
    /// or the target's layout fragment cannot be resolved.
    func revealSelection(utf16Range range: NSRange, flash: Bool, animated: Bool = false) {
        syncFrameHeightToContent()
        let clamped = clampedToLiveText(range)
        textView.setSelectedRange(clamped)
        ensureLayout(for: clamped)

        if animated, let scrollView, let targetFrame = layoutFragmentFrame(atUTF16Location: clamped.location) {
            animateScroll(toY: targetFrame.minY, in: scrollView)
        } else {
            textView.scrollRangeToVisible(clamped)
        }

        if flash {
            textView.showFindIndicator(for: clamped)
        }
    }

    /// Clamps a range built against a stale snapshot to the live text length.
    ///
    /// Uses `NSString.length` — UTF-16 code units, the unit `NSRange` is in.
    /// `String.count` counts Characters and under-clamps on emoji and CJK,
    /// which is exactly where a stale range is most likely to be wrong.
    internal func clampedToLiveText(_ range: NSRange) -> NSRange {
        let length = (textView.string as NSString).length
        let location = min(max(0, range.location), length)
        let maxLength = length - location
        return NSRange(location: location, length: min(max(0, range.length), maxLength))
    }

    /// Duration of the outline sidebar's "reveal heading" scroll animation.
    /// Must match `ScrollSyncController.jumpAnimationDuration` — this module
    /// cannot import Preview to share that constant directly, and the
    /// controller's echo-suppression window during a jump is sized against
    /// it, so a mismatch here would let a mid-animation frame slip through
    /// and be misread as a fresh, genuine scroll.
    private static let jumpAnimationDuration: TimeInterval = 0.2

    /// The layout fragment's frame at `utf16Location`, forcing layout for it
    /// first. `nil` if the location cannot be resolved against the current
    /// content storage. `internal`, not `private`, so tests can verify the
    /// jump animation's target directly rather than through the animation
    /// itself — headless tests have no real display driving `NSAnimationContext`,
    /// so a completed-animation's end state is not something a test can wait
    /// for reliably.
    func layoutFragmentFrame(atUTF16Location utf16Location: Int) -> CGRect? {
        let documentStart = contentStorage.documentRange.location
        guard let location = contentStorage.location(documentStart, offsetBy: utf16Location) else {
            return nil
        }
        var frame: CGRect?
        layoutManager.enumerateTextLayoutFragments(from: location, options: [.ensuresLayout]) { fragment in
            frame = fragment.layoutFragmentFrame
            return false
        }
        return frame
    }

    /// Animates the scroll view's clip view to `targetY`, clamped to the
    /// document's actual scrollable range.
    private func animateScroll(toY targetY: CGFloat, in scrollView: NSScrollView) {
        scrollView.contentView.wantsLayer = true
        let maxY = max(0, textView.frame.height - scrollView.contentView.bounds.height)
        let target = NSPoint(x: scrollView.contentView.bounds.origin.x, y: min(max(0, targetY), maxY))
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.jumpAnimationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            scrollView.contentView.animator().setBoundsOrigin(target)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }
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

    /// Applies any pending scroll offset once the text view is inside a scroll
    /// view. Called by ``EditorView`` after mounting the text view.
    internal func applyPendingScrollOffset() {
        guard let scrollView, let offset = pendingScrollOffset else { return }
        var origin = scrollView.contentView.bounds.origin
        origin.y = offset
        scrollView.contentView.scroll(to: origin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
        pendingScrollOffset = nil
    }
}
