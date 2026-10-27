/// Chooses whether the app follows macOS or uses one of its two theme slots.
///
/// The selected light and dark themes remain independent preferences. This
/// value only determines which slot is active right now.
public enum ThemeAppearanceMode: String, Codable, Sendable, Equatable, Hashable, CaseIterable {
    case system
    case light
    case dark

    public func resolvedAppearance(systemAppearance: ThemeAppearance) -> ThemeAppearance {
        switch self {
        case .system:
            systemAppearance
        case .light:
            .light
        case .dark:
            .dark
        }
    }
}
