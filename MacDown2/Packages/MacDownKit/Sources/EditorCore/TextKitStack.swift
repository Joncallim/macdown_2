import AppKit

/// Assembles a TextKit 2 text system. Also exposes a thin seam for a TextKit 1
/// fallback path if a concrete document is found to misbehave on TK2.
@MainActor
struct TextKitStack {
    let contentStorage: NSTextContentStorage
    let layoutManager: NSTextLayoutManager
    let textContainer: NSTextContainer
    let textView: NSTextView

    /// Whether this stack uses the legacy TextKit 1 layout engine.
    ///
    /// Currently a stub: setting this to `true` does **not** build a TK1 stack.
    /// The seam exists so a real fallback can be added if a concrete pathological
    /// file is found to misbehave on TextKit 2.
    let usesLegacyTextKit1: Bool

    /// Creates a viewport-lazy TextKit 2 stack.
    init() {
        self.init(useLegacyTextKit1: false)
    }

    /// Creates a stack. The TextKit 1 path is a stub seam only; it still builds
    /// a TK2 stack underneath regardless of `useLegacyTextKit1`.
    init(useLegacyTextKit1: Bool) {
        usesLegacyTextKit1 = useLegacyTextKit1

        contentStorage = NSTextContentStorage()
        layoutManager = NSTextLayoutManager()
        textContainer = NSTextContainer()

        // Allow the container to resize with the text view when wrapping is on.
        textContainer.widthTracksTextView = true
        textContainer.heightTracksTextView = false

        layoutManager.textContainer = textContainer
        layoutManager.replace(contentStorage)

        textView = NSTextView(frame: .zero, textContainer: textContainer)
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
    }
}
