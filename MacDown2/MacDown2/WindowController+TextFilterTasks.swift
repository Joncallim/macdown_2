import Foundation

/// Owns the lifetime of running text-filter commands, keyed by tab
/// (post-review finding #5 on the E14B remediation): without an explicit
/// owner, closing the window that started a filter did not cancel it, and a
/// later completion could mutate a text view whose document binding had
/// already been torn down. Split out of `WindowController.swift` to keep
/// the ownership/cancellation policy in one small, readable place.
extension WindowController {
    /// A running filter task plus a token identifying this specific
    /// registration, so `clearTextFilterTask` only clears a slot if a newer
    /// run has not already superseded it (`Task` itself has no identity to
    /// compare against).
    struct TextFilterTaskHandle {
        let token = UUID()
        let task: Task<Void, Never>
    }

    /// Registers `task` as the running filter for `tabID`. Any previously
    /// registered task for the same tab is cancelled first — running a new
    /// filter supersedes an in-flight one on the same document rather than
    /// letting two completions race to apply out of order (finding #1's
    /// concurrent-filter case). Returns a token to pass to
    /// `clearTextFilterTask` once the task finishes.
    @discardableResult
    func registerTextFilterTask(_ task: Task<Void, Never>, forTab tabID: UUID) -> UUID {
        textFilterTaskHandles[tabID]?.task.cancel()
        let handle = TextFilterTaskHandle(task: task)
        textFilterTaskHandles[tabID] = handle
        return handle.token
    }

    /// Clears the registration for `tabID` if it still matches `token` —
    /// i.e. no newer run has already superseded it. Call this once the
    /// task you registered has finished.
    func clearTextFilterTask(forTab tabID: UUID, token: UUID) {
        guard textFilterTaskHandles[tabID]?.token == token else { return }
        textFilterTaskHandles[tabID] = nil
    }

    /// Cancels every running filter owned by this window — called from
    /// `windowWillClose` so a filter never outlives the document/editor it
    /// was mutating.
    func cancelAllTextFilterTasks() {
        for handle in textFilterTaskHandles.values {
            handle.task.cancel()
        }
        textFilterTaskHandles = [:]
    }
}
