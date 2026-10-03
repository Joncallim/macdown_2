import SwiftUI

public extension EnvironmentValues {
    @Entry var previewOpenDocument: (@MainActor @Sendable (URL) -> Void)?
}
