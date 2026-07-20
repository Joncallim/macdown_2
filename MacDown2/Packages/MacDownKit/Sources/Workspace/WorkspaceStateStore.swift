import Foundation

/// Persists window-level workspace UI state (sidebar visibility, section expansion).
///
/// This is intentionally separate from user preferences (`AppSettings`, E13):
/// sidebar visibility is window state, not a user setting.
///
/// All implementations are accessed from the `@MainActor`-isolated `WorkspaceModel`.
@MainActor
public protocol WorkspaceStateStoring {
    var sidebarVisible: Bool { get set }
    var sidebarSectionExpanded: [String: Bool] { get set }
}

/// UserDefaults-backed `WorkspaceStateStoring` implementation.
@MainActor
public struct WorkspaceStateStore: WorkspaceStateStoring {
    public static let defaultSuiteName = "com.joncallim.macdown2.workspace"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? UserDefaults(suiteName: Self.defaultSuiteName) ?? UserDefaults.standard
    }

    public var sidebarVisible: Bool {
        get {
            // Default to visible on first launch.
            if defaults.object(forKey: Keys.sidebarVisible) == nil {
                return true
            }
            return defaults.bool(forKey: Keys.sidebarVisible)
        }
        set {
            defaults.set(newValue, forKey: Keys.sidebarVisible)
        }
    }

    public var sidebarSectionExpanded: [String: Bool] {
        get {
            guard let data = defaults.data(forKey: Keys.sidebarSectionExpanded),
                  let decoded = try? JSONDecoder().decode([String: Bool].self, from: data)
            else {
                return [:]
            }
            return decoded
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Keys.sidebarSectionExpanded)
            }
        }
    }

    private enum Keys {
        static let sidebarVisible = "sidebarVisible"
        static let sidebarSectionExpanded = "sidebarSectionExpanded"
    }
}
