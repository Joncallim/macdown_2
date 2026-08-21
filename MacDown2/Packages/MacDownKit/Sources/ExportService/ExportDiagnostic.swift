import Foundation

/// A non-fatal or fatal observation made during export composition.
///
/// Derived-content failures and unresolved-resource warnings are reported here
/// so they are visible and reviewable, never silently dropped.
public struct ExportDiagnostic: Sendable, Equatable {
    public enum Severity: Sendable, Equatable {
        case warning
        case error
    }

    public let severity: Severity
    public let message: String

    public init(severity: Severity, message: String) {
        self.severity = severity
        self.message = message
    }
}
