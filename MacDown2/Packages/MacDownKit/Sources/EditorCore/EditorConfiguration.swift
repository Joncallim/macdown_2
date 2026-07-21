import AppKit
import Foundation

/// Immutable preferences that control the editor's appearance and behavior.
///
/// The type is `Sendable` and `Equatable` so `EditorView.updateNSView` can diff
/// cheaply and only re-apply changes when a setting actually changed.
/// `NSFont` is not formally `Sendable`, but instances are immutable value-like
/// objects in practice. The unchecked conformance keeps the configuration
/// diffable across SwiftUI updates without resorting to a global actor.
public struct EditorConfiguration: @unchecked Sendable, Equatable {
    /// The base font used for body text.
    public var font: NSFont

    /// Line height multiplier applied as a base paragraph style.
    /// `1.0` uses the system default line height for the font.
    public var lineHeightMultiple: CGFloat

    /// Inset around the text inside the text view.
    public var textInsets: NSSize

    /// When `true`, lines wrap at the visible width of the text view.
    /// When `false`, the text view scrolls horizontally.
    public var wrapsLines: Bool

    /// When `true`, extra padding is added below the last line so it can scroll
    /// to the top of the viewport ("scroll past end").
    public var scrollsPastEnd: Bool

    /// Reserved for future invisibles rendering.
    public var showsInvisibles: Bool

    public init(
        font: NSFont,
        lineHeightMultiple: CGFloat = 1.0,
        textInsets: NSSize = NSSize(width: 0, height: 0),
        wrapsLines: Bool = true,
        scrollsPastEnd: Bool = true,
        showsInvisibles: Bool = false
    ) {
        self.font = font
        self.lineHeightMultiple = lineHeightMultiple
        self.textInsets = textInsets
        self.wrapsLines = wrapsLines
        self.scrollsPastEnd = scrollsPastEnd
        self.showsInvisibles = showsInvisibles
    }

    /// A sensible default configuration using the system monospaced font.
    ///
    /// This is a static constant so repeated uses of `.default` compare equal
    /// without relying on `NSFont` instance equality.
    public static let `default` = EditorConfiguration(
        font: NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular),
        lineHeightMultiple: 1.2,
        textInsets: NSSize(width: 8, height: 8),
        wrapsLines: true,
        scrollsPastEnd: true,
        showsInvisibles: false
    )
}
