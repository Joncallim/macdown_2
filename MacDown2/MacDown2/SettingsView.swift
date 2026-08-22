import SwiftUI

/// The `Settings { }` scene's pane container (`⌘,` / "MacDown 2 → Settings…").
///
/// Panes are added one epic-13 slice at a time — Markdown, Preview & Export,
/// and Formats join here in later slices (planning/epic-13-implementation.md
/// §17) rather than all landing at once.
struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettingsPane()
            }
            Tab("Editor", systemImage: "character.cursor.ibeam") {
                EditorSettingsPane()
            }
        }
        .frame(width: 480, height: 360)
    }
}
