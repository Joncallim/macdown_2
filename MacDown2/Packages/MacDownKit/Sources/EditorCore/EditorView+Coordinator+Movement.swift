import AppKit

// MARK: - Synchronized plain-arrow-key movement (EPIC-22 §6.9, §6.10, Slice 3b-iii)

// Extracted from `EditorView.swift` to keep that file under its line-count
// limit and `doCommandBy(_:)`'s own complexity down, mirroring the
// established `EditorView+Coordinator+Selection.swift` precedent (Slice 3a)
// for splitting an extension out once a file grows.

extension EditorView.Coordinator {
    /// Dispatches one of the four plain, unmodified arrow-key selectors to
    /// `EditorTextSystem`'s synchronized-movement methods. Returns `false`
    /// for every other selector, and for these four when
    /// `EditorTextSystem`'s own method declines (fewer than two active
    /// selections) — both cases mean `doCommandBy(_:)` should fall through
    /// to AppKit's unchanged native handling.
    @MainActor
    func handleSynchronizedMovement(_ selector: Selector, system: EditorTextSystem) -> Bool {
        switch selector {
        case #selector(NSResponder.moveLeft(_:)):
            system.moveAllCaretsLeft()
        case #selector(NSResponder.moveRight(_:)):
            system.moveAllCaretsRight()
        case #selector(NSResponder.moveUp(_:)):
            system.moveAllCaretsUp()
        case #selector(NSResponder.moveDown(_:)):
            system.moveAllCaretsDown()
        default:
            false
        }
    }
}
