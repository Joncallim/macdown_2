import SwiftUI

public extension EnvironmentValues {
    // How the host opens a local document a Preview link points at (in the app's
    // own window, not through Launch Services). `nil` falls back to the system.
    @Entry var previewOpenDocument: (@MainActor @Sendable (URL) -> Void)?
}
