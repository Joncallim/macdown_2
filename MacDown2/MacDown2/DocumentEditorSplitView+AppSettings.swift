import AppKit
import AppSettings
import EditorCore
import MarkdownEngine
import Workspace

/// The settings-to-domain-type conversions `DocumentEditorSplitView` reads
/// from `AppSettingsModel`. Split out of `DocumentEditorSplitView.swift` to
/// stay under the type-body-length lint budget — every view-bodied property
/// that reads these stays in the main file.
extension DocumentEditorSplitView {
    /// The default for a tab with no persisted layout of its own (a newly
    /// opened document). Kept as one shared conversion so this call site,
    /// `WorkspaceShellView`'s focused-value publisher, and
    /// `WorkspaceCommands`' Layout-menu fallback cannot drift apart and show
    /// a checkmark next to a mode that isn't what actually rendered.
    static func defaultPreviewLayout(from previewExport: PreviewExportSettings?) -> PreviewLayoutMode {
        switch previewExport?.defaultPreviewLayout {
        case .editorOnly: .editorOnly
        case .split, nil: .defaultMode
        case .previewOnly: .previewOnly
        }
    }

    /// `FontDescriptor.familyName` is a font *family* (what the Editor
    /// settings pane's picker offers via `NSFontManager.availableFontFamilies`),
    /// not a PostScript name, so resolution goes through `NSFontManager`
    /// rather than `NSFont(name:size:)`. A family the system no longer has —
    /// deleted, or a preference synced from another Mac — falls back to the
    /// same system monospaced font `EditorConfiguration.default` already
    /// uses, without touching the stored preference (epic-13-implementation.md §9).
    static func resolvedFont(from descriptor: FontDescriptor) -> NSFont {
        NSFontManager.shared.font(
            withFamily: descriptor.familyName,
            traits: [],
            weight: 5,
            size: descriptor.size
        ) ?? NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    }

    /// Only `blockDirectives` is wired to a real swift-markdown parse flag
    /// today; the other five `MarkdownParseOptions` fields stay at their
    /// documented always-on default regardless of settings
    /// (epic-13-implementation.md §2.1/§9 — verified against `ParseEngine`).
    static func markdownParseOptions(from markdownSettings: MarkdownSettings?) -> MarkdownParseOptions {
        MarkdownParseOptions(blockDirectives: markdownSettings?.parsesBlockDirectives ?? true)
    }

    static func assistConfiguration(from editorSettings: EditorSettings?) -> EditingAssistConfiguration {
        guard let editorSettings else { return .markdownDefault }
        return EditingAssistConfiguration(
            isEnabled: editorSettings.assistsEnabled,
            continuesMarkdownPrefixes: editorSettings.continuesMarkdownPrefixes,
            completesMatchingCharacters: editorSettings.completesMatchingCharacters,
            convertsTabsToSpaces: editorSettings.convertsTabsToSpaces,
            smartHome: editorSettings.smartHome,
            autoIncrementOrderedLists: editorSettings.autoIncrementOrderedLists,
            indentationWidth: editorSettings.indentationWidth
        )
    }
}
