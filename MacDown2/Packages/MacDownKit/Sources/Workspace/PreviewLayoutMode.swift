import Foundation

/// Editor/preview arrangement for one document. Codable for session
/// persistence; fraction is clamped so no pane can vanish.
public enum PreviewLayoutMode: Codable, Sendable, Equatable {
    case editorOnly
    case split(fraction: Double) // editor width fraction, clamped 0.15...0.85
    case previewOnly

    public static let defaultMode: PreviewLayoutMode = .split(fraction: 0.5)

    public var showsEditor: Bool {
        switch self {
        case .editorOnly, .split: true
        case .previewOnly: false
        }
    }

    public var showsPreview: Bool {
        switch self {
        case .previewOnly, .split: true
        case .editorOnly: false
        }
    }

    /// Returns a copy with any fraction clamped to 0.15...0.85.
    public func clamped() -> PreviewLayoutMode {
        switch self {
        case .editorOnly, .previewOnly: self
        case let .split(fraction):
            .split(fraction: min(max(fraction, 0.15), 0.85))
        }
    }
}
