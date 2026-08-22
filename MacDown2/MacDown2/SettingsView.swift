import SwiftUI

/// The `Settings { }` scene's pane container (`⌘,` / "MacDown 2 → Settings…").
///
/// Panes are added one epic-13 slice at a time — Formats joins here in a
/// later slice (planning/epic-13-implementation.md §17) rather than all
/// landing at once.
struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettingsPane()
            }
            Tab("Editor", systemImage: "character.cursor.ibeam") {
                EditorSettingsPane()
            }
            Tab("Markdown", systemImage: "text.badge.checkmark") {
                MarkdownSettingsPane()
            }
            Tab("Preview & Export", systemImage: "eye") {
                PreviewExportSettingsPane()
            }
        }
        .frame(width: 480, height: 360)
    }
}
