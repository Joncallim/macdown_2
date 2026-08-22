import Foundation

/// App-launch preferences. Folder-browser preferences (single-click open,
/// hidden-file filter) are deliberately not duplicated here — `FileTree`'s
/// `FileTreePreferences` already owns that storage; the General settings
/// pane presents it directly instead of re-homing it.
public struct GeneralSettings: Codable, Sendable, Equatable {
    public enum LaunchBehavior: String, Codable, Sendable {
        case restorePreviousSession
        case startWithNewDocument
    }

    public var launchBehavior: LaunchBehavior

    public init(launchBehavior: LaunchBehavior = .restorePreviousSession) {
        self.launchBehavior = launchBehavior
    }

    public static let `default` = GeneralSettings()
}
