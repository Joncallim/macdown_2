import Foundation

/// Default preview layout for newly opened tabs, and default export choices
/// used to seed the export panel. These are defaults only: an existing
/// tab's persisted layout is untouched, and the export panel remains fully
/// user-editable per export — nothing here reaches into the export
/// composer's fixed template/layout/resource-root/budget/metadata-policy
/// pipeline (see epic-13-implementation.md §4, invariant 4).
public struct PreviewExportSettings: Codable, Sendable, Equatable {
    public enum DefaultPreviewLayout: String, Codable, Sendable {
        case editorOnly, split, previewOnly
    }

    public enum DefaultExportFormat: String, Codable, Sendable {
        case standaloneHTML, selfContainedHTML, pdf
    }

    public enum DefaultExportStyle: String, Codable, Sendable {
        case embedded, linked
    }

    public var defaultPreviewLayout: DefaultPreviewLayout
    public var defaultExportFormat: DefaultExportFormat
    public var defaultExportStyle: DefaultExportStyle

    public init(
        defaultPreviewLayout: DefaultPreviewLayout = .split,
        defaultExportFormat: DefaultExportFormat = .standaloneHTML,
        defaultExportStyle: DefaultExportStyle = .embedded
    ) {
        self.defaultPreviewLayout = defaultPreviewLayout
        self.defaultExportFormat = defaultExportFormat
        self.defaultExportStyle = defaultExportStyle
    }

    public static let `default` = PreviewExportSettings()
}
