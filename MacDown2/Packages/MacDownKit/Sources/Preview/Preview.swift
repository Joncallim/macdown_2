import FileCore
import MarkdownEngine
import SwiftUI

/// Preview — format router and lightweight preview views for the workspace shell.
///
/// See planning/epics/ and planning/MIGRATION_PLAN.md § 4 for the full role.
/// For EPIC-02 the preview is read-only and intentionally simple: Markdown is
/// rendered to attributed text via `MarkdownEngine`, HTML is shown in a
/// `WKWebView`, and other formats display a placeholder. Richer preview
/// contributions (math, diagrams, scroll sync) arrive in later epics.
public enum PreviewModule {
    public static let moduleName = "Preview"
}

/// The kind of preview a format supports in the workspace shell.
public enum PreviewKind: Sendable, Equatable {
    case markdown
    case html
    case jsonOutline
    case none
}

/// Routes `FileFormat`'s typed `PreviewCapability` to the preview kind used
/// by the content area. A format never silently inherits another format's
/// renderer: capabilities without a registered kind degrade to `.none`.
public enum PreviewRouter {
    public static func previewKind(for format: FileFormat) -> PreviewKind {
        switch format.previewCapability {
        case .markdown:
            .markdown
        case .htmlSourceAndRendered:
            .html
        case .jsonOutline:
            .jsonOutline
        case .none:
            .none
        }
    }

    /// The mode the preview pane should start in for this format. Falls back
    /// to `.rendered` for rendered capabilities when the format omits an
    /// explicit default.
    public static func defaultPreviewMode(for format: FileFormat) -> PreviewMode? {
        if let defaultPreviewMode = format.defaultPreviewMode {
            return defaultPreviewMode
        }
        switch format.previewCapability {
        case .markdown, .htmlSourceAndRendered:
            return .rendered
        case .jsonOutline:
            return .outline
        case .none:
            return nil
        }
    }

    /// Whether `mode` is a valid preview display mode for this format.
    public static func supports(_ mode: PreviewMode, for format: FileFormat) -> Bool {
        format.supportedPreviewModes.contains(mode)
    }
}
