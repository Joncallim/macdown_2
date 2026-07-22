import Themes

/// The internal seam the app talks to. One instance per open document/text system.
@MainActor
public protocol SyntaxHighlighting: AnyObject {
    /// The language identifier currently in use (nil = plain text).
    var languageID: String? { get }

    /// Recolour the visible range for a new theme WITHOUT reparsing.
    func applyTheme(_ theme: Theme)

    /// Swap language (e.g. after Save As changes the format). Rebuilds the parser.
    func setLanguage(_ highlightLanguageID: String?)

    /// Force a full re-highlight (external reload / conflict resolution reset the text).
    func invalidateAll()

    /// Break references so the NSTextView graph deallocates. Call on tab close.
    func tearDown()
}
