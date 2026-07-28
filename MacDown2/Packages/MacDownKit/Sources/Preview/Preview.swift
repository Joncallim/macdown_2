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
    case none
}

/// Routes `FileFormat` to the preview kind used by the content area.
public enum PreviewRouter {
    public static func previewKind(for format: FileFormat) -> PreviewKind {
        switch format.id {
        case "markdown":
            .markdown
        case "html":
            .html
        default:
            format.previewCapability == .rendered ? .markdown : .none
        }
    }
}
