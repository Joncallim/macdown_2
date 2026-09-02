import SwiftUI

/// The `Settings { }` scene's pane container (`⌘,` / "MacDown 2 → Settings…").
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
            Tab("Formats", systemImage: "tablecells") {
                FormatSettingsPane()
            }
        }
        .frame(width: 480, height: 360)
    }
}
