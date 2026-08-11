import Foundation

@MainActor
extension ExternalFileController {
    func saveAs() async {
        await owner?.saveDocumentAs()
    }

    func retryRecoveryCleanup() {
        guard !disposed, let recoveryRetryAction else { return }
        enqueueRecovery(
            recoveryRetryAction,
            resumeMoveWhenComplete: true,
            resumeCloseWhenComplete: true
        )
    }
}
