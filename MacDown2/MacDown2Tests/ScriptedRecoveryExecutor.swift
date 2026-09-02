import FileCore
import Foundation
@testable import MacDown2

/// A scripted `RecoveryActionExecuting` fake for `ExternalFileControllerRecoveryTests`.
/// Split into its own file — it's a standalone fake with no dependency on the
/// struct it supports — to stay under the file-length lint budget.
actor ScriptedRecoveryExecutor: RecoveryActionExecuting {
    private var failures: Set<ExternalFileController.RecoveryRetryKind> = []
    private(set) var calls: [ExternalFileController.RecoveryRetryKind] = []

    func failNext(_ kind: ExternalFileController.RecoveryRetryKind) {
        failures.insert(kind)
    }

    func persist(_: FileDocument) -> Bool {
        calls.append(.persist)
        return failures.remove(.persist) == nil
    }

    func remove(
        _: RecoveryBuffer,
        id: String,
        version _: UInt,
        epoch _: UUID
    ) -> RecoveryCleanupResult {
        calls.append(.remove)
        if failures.remove(.remove) != nil {
            return .failed(.removalFailed(URL(fileURLWithPath: id), 13))
        }
        return .removed
    }

    func migrate(
        _: RecoveryBuffer,
        oldID: String,
        sourceEpoch _: UUID,
        document _: FileDocument
    ) -> RecoveryMigrationOutcome {
        calls.append(.migrate)
        if failures.remove(.migrate) != nil {
            return .failed(.removalFailed(URL(fileURLWithPath: oldID), 13))
        }
        return .migrated
    }

    func retire(_: RecoveryBuffer, id: String, epoch _: UUID) -> RecoveryCleanupResult {
        calls.append(.retire)
        if failures.remove(.retire) != nil {
            return .failed(.removalFailed(URL(fileURLWithPath: id), 13))
        }
        return .removed
    }
}
