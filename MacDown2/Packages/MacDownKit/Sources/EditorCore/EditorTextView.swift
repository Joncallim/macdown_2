import AppKit

/// `NSTextView` subclass that draws TextKit-2-safe invisible characters
/// (spaces, tabs, line endings) directly within the text content area
/// (epic-22-implementation.md §6.8, §17 Slice 2c).
///
/// This is a `draw(_:)` override rather than a separate overlay `NSView`:
/// AppKit already calls `draw(_:)` with a viewport-clamped dirty rect on
/// exactly the right schedule (scroll, edit, initial display), so a second
/// view would need to reinvent that scroll/invalidation synchronization for
/// no benefit. Never touches `layoutManager` (the legacy TextKit 1
/// accessor) — only `textLayoutManager`, the TextKit 2 API.
@MainActor
public final class EditorTextView: NSTextView {
    /// Set once by `EditorTextSystem.init`, after `self` is fully
    /// initialized, so this view can route multi-selection typing/delete
    /// through `EditorTextSystem`'s `EditorEditTransaction` chokepoint
    /// (§6.9, §7.2, Slice 3a). Weak: the text system owns this view (via
    /// `TextKitStack`), never the reverse.
    weak var owningSystem: EditorTextSystem?

    /// Public: `EditorTextSystem.apply(_:)` sets this from
    /// `EditorConfiguration.showsInvisibles`.
    public var showsInvisibles = false {
        didSet {
            guard showsInvisibles != oldValue else { return }
            needsDisplay = true
        }
    }

    /// Public: the `Highlighting` module's `NeonSyntaxHighlighter.applyChrome(theme:)`
    /// sets this from `Theme.chrome.invisibles`.
    public var invisiblesColor: NSColor = .tertiaryLabelColor {
        didSet {
            guard showsInvisibles else { return }
            needsDisplay = true
        }
    }

    override public func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if showsInvisibles, let textLayoutManager {
            drawInvisibles(in: dirtyRect, layoutManager: textLayoutManager)
        }
        drawSecondaryCarets()
    }

    /// Multi-selection typing (§6.9, §7.2): when more than one selection is
    /// active, `owningSystem.applyMultiCursorInsert(_:)` replaces every one
    /// of them with the typed text and returns `true`; `super` is not
    /// called in that case, since calling it too would insert the text a
    /// second time at whichever range AppKit itself considers primary.
    /// `replacementRange.location != NSNotFound` means this call already
    /// targets one specific, explicit range — including each of the N
    /// individual sub-edits `EditorEditTransaction.apply(_:)` itself makes
    /// through this same override while fanning out — so those always fall
    /// through to `super` unchanged, exactly as before this override
    /// existed. This never fires for bare multi-caret typing (no selected
    /// text, more than one insertion point): that state cannot exist in
    /// `selectedRanges` in the first place — see §6.9's architecture-
    /// correction note.
    override public func insertText(_ string: Any, replacementRange: NSRange) {
        if replacementRange.location == NSNotFound,
           let owningSystem, let text = string as? String,
           owningSystem.applyMultiCursorInsert(text) {
            return
        }
        super.insertText(string, replacementRange: replacementRange)
    }

    /// Multi-selection delete (§6.9, §7.2): `deleteBackward`/`deleteForward`
    /// share one selection-deleting implementation, since every range in a
    /// real multi-selection is non-empty (see
    /// `applyMultiCursorDeleteSelection()`'s doc comment) and deleting a
    /// selection's own content is direction-independent.
    override public func deleteBackward(_ sender: Any?) {
        if let owningSystem, owningSystem.applyMultiCursorDeleteSelection() {
            return
        }
        super.deleteBackward(sender)
    }

    override public func deleteForward(_ sender: Any?) {
        if let owningSystem, owningSystem.applyMultiCursorDeleteSelection() {
            return
        }
        super.deleteForward(sender)
    }

    /// Multi-selection paste (§6.9, §7.2) needs its own override, separate
    /// from `insertText`: found empirically (a real, pasteboard-backed test)
    /// that `NSTextView.paste(_:)` performs the operation as two SEPARATE
    /// `insertText` calls — an empty-string "delete the current selection(s)"
    /// call, then a text "insert" call — rather than one. Once the first
    /// call's multi-range delete correctly empties every selection, AppKit's
    /// own selection collapses to a single caret (the same collapse this
    /// file's `insertText`/`deleteBackward` docs already describe for
    /// multiple simultaneous zero-length ranges), so the second call would
    /// only ever insert the pasted text at ONE location — silently losing
    /// the other selections' paste. Reading the pasteboard directly and
    /// routing it through `applyMultiCursorInsert(_:)` in one step, before
    /// AppKit's own two-step sequence begins, avoids that entirely. Plain
    /// string only, matching this editor's plain-text-only design
    /// (`EditorTextSystem.apply(_:)` already sets `isRichText = false`).
    override public func paste(_ sender: Any?) {
        if let owningSystem, let text = NSPasteboard.general.string(forType: .string),
           owningSystem.applyMultiCursorInsert(text) {
            return
        }
        super.paste(sender)
    }

    /// Option-click add/remove caret (§6.10, Slice 3b-ii). A plain
    /// (single-click) Option-click resolves the click point to a character
    /// offset and toggles a secondary caret there via
    /// `EditorTextSystem.toggleSecondaryCaret(at:)`; anything else (no
    /// Option, or more than one click) falls through to `super.mouseDown(_:)`
    /// unchanged. Not calling `super` for a handled Option-click also means
    /// AppKit's own internal drag-tracking loop never starts for it, so an
    /// Option-*drag* does nothing beyond placing the initial caret — the
    /// correct minimal scope here; rectangular/column selection via
    /// Option-drag is Slice 3b-iv's own, separate feature.
    ///
    /// Point-to-offset resolution uses `NSTextInputClient.characterIndex(for:)`
    /// (screen-space), confirmed empirically against this exact TextKit 2
    /// stack (round-tripped through `firstRect(forCharacterRange:)`'s
    /// already-verified offset-to-point mapping, exact for 7 offsets
    /// spanning a line wrap) — a different, more precise tool than
    /// `EditorTextSystem+Scroll.swift`'s `topVisibleUTF16Offset`, which only
    /// ever needed fragment-level granularity, not an exact character
    /// position within a line.
    override public func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.option), event.clickCount == 1, let owningSystem, let window {
            let screenPoint = window.convertPoint(toScreen: event.locationInWindow)
            if owningSystem.toggleSecondaryCaret(at: characterIndex(for: screenPoint)) {
                return
            }
        }
        super.mouseDown(with: event)
    }

    /// Viewport-bounded: starts at the fragment intersecting `dirtyRect`'s
    /// origin and stops as soon as a fragment's frame is entirely below
    /// `dirtyRect`, mirroring `EditorTextSystem+Gutter.swift`'s
    /// `enumerateVisibleLineFragments` and `EditorTextSystem+Scroll.swift`'s
    /// `topVisibleUTF16Offset` — never a whole-document walk.
    ///
    /// `dirtyRect` (from `draw(_:)`) is in the text view's own bounds space,
    /// which includes `textContainerInset` — but `NSTextLayoutManager`'s
    /// fragment geometry (`layoutFragmentFrame`, `textLayoutFragment(for:)`)
    /// is in the text container's own coordinate space, which excludes it.
    /// Converting to container space for the lookup/bounds check, then back
    /// to view space for each marker's final draw position, is required:
    /// getting this wrong makes every lookup silently miss whenever
    /// `textContainerInset` is nonzero — e.g. `scrollsPastEnd`'s
    /// bottom-overscroll padding, which symmetrically inflates
    /// `textContainerInset.height` at the top too, per `NSTextView.textContainerInset`'s
    /// documented top+bottom (and left+right) symmetry. Found by hostile
    /// review of PR #127: invisibles drew correctly for a from-scratch,
    /// `(0, 0)`-origin full-window paint (every previously-shipped test's
    /// only scenario) but silently drew nothing for an ordinary, genuinely
    /// scrolled dirty rect — exactly what AppKit issues on real scrolling
    /// and per-line edit invalidation.
    private func drawInvisibles(in dirtyRect: NSRect, layoutManager: NSTextLayoutManager) {
        let inset = textContainerInset
        let containerOrigin = CGPoint(x: dirtyRect.origin.x - inset.width, y: dirtyRect.origin.y - inset.height)
        guard let startFragment = layoutManager.textLayoutFragment(for: containerOrigin) else { return }
        let font = font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: invisiblesColor]
        let containerDirtyMinY = dirtyRect.minY - inset.height
        let containerDirtyMaxY = dirtyRect.maxY - inset.height

        layoutManager.enumerateTextLayoutFragments(
            from: startFragment.rangeInElement.location,
            options: [.ensuresLayout]
        ) { fragment in
            let fragmentFrame = fragment.layoutFragmentFrame
            guard fragmentFrame.minY < containerDirtyMaxY else { return false }
            guard fragmentFrame.maxY > containerDirtyMinY else { return true }

            for lineFragment in fragment.textLineFragments {
                let lineText = lineFragment.attributedString
                    .attributedSubstring(from: lineFragment.characterRange).string
                for marker in EditorInvisiblesLayout.markers(in: lineText) {
                    let characterIndex = lineFragment.characterRange.location + marker.localUTF16Offset
                    let point = lineFragment.locationForCharacter(at: characterIndex)
                    let glyphString = marker.glyph as NSString
                    let size = glyphString.size(withAttributes: attributes)
                    let rect = NSRect(
                        x: fragmentFrame.minX + point.x + inset.width,
                        y: fragmentFrame.minY + lineFragment.typographicBounds.minY + inset.height,
                        width: size.width,
                        height: max(size.height, lineFragment.typographicBounds.height)
                    )
                    glyphString.draw(in: rect, withAttributes: attributes)
                }
            }
            return true
        }
    }

    /// Multi-caret rendering foundation (§6.9's architecture-correction
    /// note, §6.10, Slice 3b-i): every caret beyond the primary one lives
    /// only in `EditorTextSystem.selectionSet`, never in
    /// `textView.selectedRanges` — `NSTextView` cannot represent more than
    /// one simultaneous zero-length range there, confirmed empirically, so
    /// AppKit's own native insertion-point rendering only ever shows the
    /// primary caret. This pass draws a solid (deliberately non-blinking —
    /// see §6.10 on why synchronizing a second timer against AppKit's own
    /// private blink cadence is unnecessary complexity for a cosmetic
    /// property) vertical bar at every OTHER caret's position, in the same
    /// color AppKit uses for the real one.
    ///
    /// Uses `NSTextInputClient.firstRect(forCharacterRange:actualRange:)`
    /// (confirmed empirically, against this exact TextKit 2 stack, to
    /// return correct, already-coordinate-converted screen-space rects for
    /// an arbitrary zero-length range) rather than hand-deriving
    /// paragraph-relative line-fragment geometry the way `drawInvisibles`
    /// must: that manual approach exists there because it draws MANY glyphs
    /// per visible line from one bounded fragment walk; here there are only
    /// ever a handful of explicit, already-known offsets to resolve, so the
    /// built-in, Apple-maintained API already designed for exactly this
    /// (IME candidate-window positioning) is the lower-risk choice — not
    /// re-deriving fragile geometry math this codebase has already been
    /// burned by once (§6.8/§6.9's own invisibles coordinate-space bug).
    ///
    /// Not viewport-pre-filtered before calling `firstRect` for each
    /// secondary caret, unlike `drawInvisibles`'s bounded fragment walk:
    /// `EditorTextViewSecondaryCaretTests`'s 100-caret stress test measures
    /// this directly against the §11 performance budget rather than
    /// pre-emptively adding an unverified viewport heuristic: this method
    /// is called once per real display pass (not once per keystroke on an
    /// otherwise-unrelated part of the document), and it costs one call to
    /// an already-fast, layout-caching API per caret. If a future, much
    /// larger cursor count is found to actually violate the budget, add
    /// the filter then, informed by a real measurement rather than a guess.
    private func drawSecondaryCarets() {
        guard let owningSystem else { return }
        let selection = owningSystem.selectionSet
        guard selection.isMultiple else { return }
        let secondaryOffsets = selection.ranges.enumerated()
            .filter { index, range in index != selection.primaryIndex && range.length == 0 }
            .map(\.element.location)
        guard !secondaryOffsets.isEmpty, let window else { return }

        let color = insertionPointColor ?? .labelColor
        for offset in secondaryOffsets {
            var actualRange = NSRange(location: NSNotFound, length: 0)
            let screenRect = firstRect(
                forCharacterRange: NSRange(location: offset, length: 0),
                actualRange: &actualRange
            )
            guard actualRange.location != NSNotFound else { continue }
            var viewRect = convert(window.convertFromScreen(screenRect), from: nil)
            viewRect.size.width = max(viewRect.width, 1.5)
            color.setFill()
            NSBezierPath(rect: viewRect).fill()
        }
    }
}
