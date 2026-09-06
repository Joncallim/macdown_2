import Foundation

/// A renderer-neutral diagnostic a contribution reports about its own
/// result. Always forwarded by callers whether or not the content it
/// describes ends up placed, mirroring `ExportService.ExportDiagnostic`'s
/// existing "diagnostics a contribution carries are always forwarded"
/// contract (epic-14-implementation.md §2.1).
public struct ContributionDiagnostic: Sendable, Equatable {
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
