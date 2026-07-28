import Foundation

/// Thickness of the divider between the editor and preview panes.
public let dividerWidth: CGFloat = 1

// MARK: - Width math

/// Width calculations for the editor and preview panes.
public enum PreviewPaneWidths {
    public static func editorWidth(in totalWidth: CGFloat, layout: PreviewLayoutMode) -> CGFloat {
        switch layout {
        case .editorOnly:
            totalWidth
        case .previewOnly:
            0
        case let .split(fraction):
            max(0, totalWidth * fraction)
        }
    }

    public static func previewWidth(in totalWidth: CGFloat, layout: PreviewLayoutMode) -> CGFloat {
        switch layout {
        case .editorOnly:
            0
        case .previewOnly:
            totalWidth
        case .split:
            max(0, totalWidth - editorWidth(in: totalWidth, layout: layout) - dividerWidth)
        }
    }
}
