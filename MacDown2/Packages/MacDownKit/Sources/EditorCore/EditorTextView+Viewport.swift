import AppKit

/// Presentation restoration runs at layout/paint boundaries; actual wheel input retires it first.
public extension EditorTextView {
    override func layout() {
        super.layout()
        owningSystem?.restorePresentationViewportIfNeeded()
    }

    override func scrollWheel(with event: NSEvent) {
        owningSystem?.cancelPresentationViewportRestoration()
        super.scrollWheel(with: event)
    }
}
