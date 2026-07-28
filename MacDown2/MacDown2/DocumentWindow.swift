import AppKit
import Workspace

/// Document window that routes layout shortcuts to the coordinator when the
/// SwiftUI `Commands` scene does not handle them (e.g. when the placeholder
/// `WindowGroup` window is closed and the scene becomes inactive).
@MainActor
final class DocumentWindow: NSWindow {
    weak var coordinator: WindowCoordinator?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if handleLayoutShortcut(event) {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    private func handleLayoutShortcut(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }

        let requiredModifiers: NSEvent.ModifierFlags = [.command, .option]
        let ignoredModifiers: NSEvent.ModifierFlags = [.capsLock, .numericPad, .help, .function]
        let flags = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting(ignoredModifiers)
        guard flags == requiredModifiers else { return false }

        guard let characters = event.charactersIgnoringModifiers,
              characters.count == 1 else { return false }

        switch characters {
        case "1":
            coordinator?.setPreviewLayout(.editorOnly)
            return true
        case "2":
            coordinator?.setPreviewLayout(.split(fraction: 0.5))
            return true
        case "3":
            coordinator?.setPreviewLayout(.previewOnly)
            return true
        default:
            return false
        }
    }
}
