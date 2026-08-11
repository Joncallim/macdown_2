import AppKit

/// The editor state preserved across a clean external replacement.
///
/// Both the selected range and all editor range APIs are UTF-16 based.
public struct EditorViewportSnapshot: Equatable {
    public let selectedRange: NSRange
    public let scrollOffset: CGFloat

    public init(selectedRange: NSRange, scrollOffset: CGFloat) {
        self.selectedRange = selectedRange
        self.scrollOffset = scrollOffset
    }
}
