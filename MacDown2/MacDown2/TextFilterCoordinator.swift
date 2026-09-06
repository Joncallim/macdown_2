import AppKit
import EditorCore
import Foundation
import TextFilters
import Workspace

/// Orchestrates running one discovered text-filter command against the key
/// window's active editor (epic-14-implementation.md §7.2, §17 Slice 6).
///
/// A value type with no stored state of its own, mirroring
/// `ExportCoordinator`'s shape: the window coordinator hands one out per
/// menu/palette evaluation, and nothing must survive between them.
@MainActor
struct TextFilterCoordinator {
    private let coordinator: WindowCoordinator

    init(coordinator: WindowCoordinator) {
        self.coordinator = coordinator
    }

    /// `true` when the key window has an active document with a live
    /// editor text system. Text filters operate on plain selected/whole
    /// text (§5) — no format restriction, unlike the Markdown- and
    /// JSON-specific formatting commands.
    var canRunTextFilters: Bool {
        keyEditingTarget != nil
    }

    /// Runs `command` against the key window's active editor: the current
    /// selection when non-empty, else the whole document (§7.2, J4/J6).
    /// Applies the output as exactly one undoable edit on success; shows
    /// an alert naming the command on failure, except cancellation, which
    /// is a deliberate withdrawal, not an error (§9).
    func run(_ command: TextFilterCommand) async {
        guard let target = keyEditingTarget else { return }

        let selection = target.textSystem.textView.selectedRange()
        let liveText = target.textSystem.textView.string as NSString
        let usesWholeDocument = selection.length == 0
        let input = usesWholeDocument ? (liveText as String) : liveText.substring(with: selection)

        do {
            let output = try await TextFilterRunner().run(
                command, input: input, documentURL: target.documentURL
            )
            apply(output, usesWholeDocument: usesWholeDocument, range: selection, to: target, named: command.name)
        } catch TextFilterError.cancelled {
            // The user withdrew the action (e.g. closed the window mid-run);
            // there is nothing to report (§9).
        } catch {
            await presentFailure(error, commandName: command.name)
        }
    }

    // MARK: - Applying a successful result

    private func apply(
        _ output: String,
        usesWholeDocument: Bool,
        range: NSRange,
        to target: TextFilterEditingTarget,
        named commandName: String
    ) {
        let undoActionName = commandName
        if usesWholeDocument {
            target.textSystem.applyDocumentReplacement(output, undoActionName: undoActionName)
            return
        }

        let textView = target.textSystem.textView
        let liveLength = (textView.string as NSString).length
        // The document may have changed while the command ran (§8): the
        // captured range is clamped to the live text rather than rejected,
        // exactly like `applyDocumentReplacement`'s own selection handling.
        let clampedRange = Self.clampedRange(range, toLength: liveLength)
        let location = clampedRange.location

        textView.breakUndoCoalescing()
        textView.insertText(output, replacementRange: clampedRange)
        let caret = location + (output as NSString).length
        textView.setSelectedRange(NSRange(location: caret, length: 0))
        if target.textSystem.undoManager.canUndo {
            target.textSystem.undoManager.setActionName(undoActionName)
        }
        textView.breakUndoCoalescing()
    }

    /// Clamps `range` against the live text length rather than rejecting
    /// it outright — a stale selection (an incompatible edit happened
    /// while the command ran) becomes a fresh insertion at the nearest
    /// valid position instead of a silently dropped result (§8).
    nonisolated static func clampedRange(_ range: NSRange, toLength liveLength: Int) -> NSRange {
        let location = min(max(0, range.location), liveLength)
        let length = min(max(0, range.length), liveLength - location)
        return NSRange(location: location, length: length)
    }

    // MARK: - Failure presentation

    private func presentFailure(_ error: Error, commandName: String) async {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "\"\(commandName)\" Failed"
        alert.informativeText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        if let window = NSApp.keyWindow {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                alert.beginSheetModal(for: window) { _ in continuation.resume() }
            }
        } else {
            alert.runModal()
        }
    }

    // MARK: - Target resolution

    private struct TextFilterEditingTarget {
        let textSystem: EditorTextSystem
        let documentURL: URL?
    }

    private var keyEditingTarget: TextFilterEditingTarget? {
        guard let controller = coordinator.controllers.first(where: { $0.window == NSApp.keyWindow }),
              let activeTab = controller.model.tabStore.activeTab,
              let textSystem = controller.editorStore.existingSystem(for: activeTab.id.uuidString)
        else {
            return nil
        }
        return TextFilterEditingTarget(textSystem: textSystem, documentURL: controller.model.activeDocument?.fileURL)
    }
}
