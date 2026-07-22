import AppKit
import EditorCore
import Neon
import RangeState
import SwiftTreeSitter
import SwiftTreeSitterLayer
import Themes

/// Concrete highlighter: wraps Neon's `TextViewHighlighter` over an E04 `EditorTextSystem`.
@MainActor
public final class NeonSyntaxHighlighter: SyntaxHighlighting {
    private let textSystem: EditorTextSystem
    private let registry: GrammarRegistry
    private var currentTheme: Theme
    private var highlighter: TextViewHighlighter?
    public private(set) var languageID: String?
    private let baseFont: NSFont

    /// - textSystem: the E04 system whose `.textView` we attach to.
    /// - languageID: `FileFormat.highlightLanguageID` (nil / unknown ⇒ plain text + chrome only).
    /// - theme: initial theme; chrome is applied to the text view immediately.
    /// - registry: shared grammar registry.
    public init(
        textSystem: EditorTextSystem,
        languageID: String?,
        theme: Theme,
        registry: GrammarRegistry
    ) {
        self.textSystem = textSystem
        self.languageID = languageID
        self.registry = registry
        currentTheme = theme
        baseFont = textSystem.textView.font
            ?? NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

        applyChrome(theme: theme)
        buildHighlighter(languageID: languageID)
    }

    // MARK: - SyntaxHighlighting

    public func applyTheme(_ theme: Theme) {
        currentTheme = theme
        applyChrome(theme: theme)
        highlighter?.invalidate(.all)
    }

    public func setLanguage(_ highlightLanguageID: String?) {
        guard languageID != highlightLanguageID else { return }
        languageID = highlightLanguageID
        highlighter = nil
        buildHighlighter(languageID: highlightLanguageID)
    }

    public func invalidateAll() {
        highlighter?.invalidate(.all)
    }

    public func tearDown() {
        highlighter = nil
    }

    // MARK: - Internal

    private func applyChrome(theme: Theme) {
        let textView = textSystem.textView
        textView.backgroundColor = theme.chrome.background.nsColor
        textView.textColor = theme.chrome.foreground.nsColor
        textView.insertionPointColor = theme.chrome.caret.nsColor
        textView.selectedTextAttributes = [.backgroundColor: theme.chrome.selection.nsColor]
    }

    private func buildHighlighter(languageID: String?) {
        guard let config = registry.configuration(for: languageID) else { return }

        do {
            let attributeProvider: TokenAttributeProvider = { [weak self] token in
                guard let self else { return [:] }
                let style = currentTheme.style(for: token.name)
                var attrs: [NSAttributedString.Key: Any] = [
                    .foregroundColor: (style?.color ?? currentTheme.chrome.foreground).nsColor,
                ]
                if let style {
                    attrs[.font] = styledFont(bold: style.bold, italic: style.italic)
                    if style.underline {
                        attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
                    }
                }
                return attrs
            }

            highlighter = try TextViewHighlighter(
                textView: textSystem.textView,
                configuration: TextViewHighlighter.Configuration(
                    languageConfiguration: config,
                    attributeProvider: attributeProvider,
                    languageProvider: registry.languageProvider,
                    locationTransformer: Self.locationTransformer(for: textSystem.textView)
                )
            )
        } catch {
            // Graceful degradation: leave highlighter nil, plain text + chrome.
            highlighter = nil
        }
    }

    private func styledFont(bold: Bool, italic: Bool) -> NSFont {
        var traits: NSFontDescriptor.SymbolicTraits = []
        if bold {
            traits.insert(.bold)
        }
        if italic {
            traits.insert(.italic)
        }

        let descriptor = baseFont.fontDescriptor.withSymbolicTraits(traits)
        return NSFont(descriptor: descriptor, size: baseFont.pointSize) ?? baseFont
    }

    /// Maps a UTF-16 offset to a tree-sitter `Point`.
    ///
    /// `row` = number of `\n` before the offset; `column` = UTF-16 code-unit
    /// distance back to the previous `\n` (or string start).
    ///
    /// Uses a lazily-built line-offset table with binary search for O(log n)
    /// per-call performance instead of O(n) substring scanning.
    static func locationTransformer(for textView: NSTextView) -> (Int) -> Point? {
        var lineOffsets: [Int]?
        var cachedLength = 0

        return { offset in
            let string = textView.string as NSString
            let clamped = max(0, min(offset, string.length))

            // Rebuild the line-offset table when the document length changes
            // (e.g., after an edit). This keeps row calculations correct for
            // incremental reparse positions.
            if lineOffsets == nil || cachedLength != string.length {
                cachedLength = string.length
                var offsets = [0]
                let length = string.length
                var searchRange = NSRange(location: 0, length: length)
                while searchRange.length > 0 {
                    let newlineRange = string.range(of: "\n", options: [], range: searchRange)
                    guard newlineRange.location != NSNotFound else { break }
                    offsets.append(newlineRange.location + 1)
                    let nextStart = newlineRange.location + 1
                    guard nextStart < length else { break }
                    searchRange = NSRange(location: nextStart, length: length - nextStart)
                }
                lineOffsets = offsets
            }

            guard let offsets = lineOffsets, !offsets.isEmpty else {
                return Point(row: 0, column: clamped)
            }

            // Binary search for the row containing `clamped`.
            var low = 0, high = offsets.count - 1
            while low <= high {
                let mid = (low + high) / 2
                if offsets[mid] <= clamped {
                    low = mid + 1
                } else {
                    high = mid - 1
                }
            }
            let row = high
            let column = clamped - offsets[row]
            return Point(row: row, column: column)
        }
    }
}
