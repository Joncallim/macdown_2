import AppSettings
import FileCore

/// The Formats pane's settings-to-domain-type conversion. Split out of
/// `WindowCoordinator.swift` to stay under the file-length lint budget —
/// same pattern as `WindowCoordinator+SessionRestore.swift` and
/// `DocumentEditorSplitView+AppSettings.swift`.
extension WindowCoordinator {
    /// Resolves the default-encoding preference for a brand-new, never-saved
    /// document (`newDocument(addAsTab:)`'s only caller). UTF-16 resolves to
    /// the explicit little-endian, BOM-marked form `FileStore`'s own read
    /// path already detects (`FileStore+Encoding.swift`); any other stored
    /// value — including a future or corrupted one — falls back to UTF-8
    /// rather than being passed through unchecked
    /// (epic-13-implementation.md §10). Never applied to an already-open or
    /// already-saved document (D10, §4 invariant 2).
    static func defaultEncoding(from formats: FormatSettings) -> FileEncodingMetadata {
        switch formats.defaultEncodingForNewDocuments {
        case "utf-16": FileEncodingMetadata(encoding: .utf16LittleEndian, bom: .utf16LittleEndian)
        default: .utf8Default
        }
    }
}
