import AppKit
import EditorCore
import SwiftUI

/// The Ctrl-G "Go to Line/Column" panel (epic-22-implementation.md §6.7,
/// §17 Slice 2b).
///
/// Ownership mirrors `CommandPalettePanel` exactly (see its own doc comment
/// for the full rationale): `NSPanel.isReleasedWhenClosed` defaults to
/// `false`, so `WindowCoordinator` holds this panel strongly for exactly as
/// long as it is open (`goToLinePanel` in `WindowCoordinator+GoToLine.swift`),
/// releasing it via `windowWillClose` → `goToLinePanelDidClose`. Unlike the
/// command palette (app-wide, can act on any window), this panel only ever
/// targets the one document it was opened from, so it resolves its target
/// `EditorTextSystem` once, from `originController`, the same way
/// `TextFilterCoordinator.editingTarget(for:)` resolves a text filter's
/// target — not via `NSApp.keyWindow` at submit time, which would silently
/// jump in the wrong window if focus moved while the panel was open.
@MainActor
final class GoToLinePanel: NSPanel, NSWindowDelegate {
    private weak var coordinator: WindowCoordinator?
    private(set) weak var originController: WindowController?

    convenience init(coordinator: WindowCoordinator, originController: WindowController?) {
        self.init(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 100),
            styleMask: [.titled, .fullSizeContentView, .closable],
            backing: .buffered,
            defer: false
        )
        self.coordinator = coordinator
        self.originController = originController
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        level = .floating
        delegate = self

        let view = GoToLineView(
            onSubmit: { [weak self] input in
                self?.jump(to: input)
                self?.close()
            },
            onCancel: { [weak self] in self?.close() }
        )
        contentView = NSHostingView(rootView: view)
    }

    /// Parses `input`, resolves the origin's active `EditorTextSystem`, and
    /// jumps. Invalid or out-of-range input never crashes or no-ops
    /// silently on a parse failure — an unparsable line defaults to line 1,
    /// and `EditorLineIndex.utf16Offset(forLine:column:in:)`'s own clamping
    /// handles genuinely out-of-range numbers, matching this type's
    /// clamping convention throughout (§6.7). Not `private`: called directly
    /// by `GoToLinePanelTests` — the exact production code path, since
    /// `GoToLineView`'s `onSubmit` closure forwards to this with no
    /// intervening logic of its own.
    func jump(to input: String) {
        guard let originController,
              let activeTab = originController.model.tabStore.activeTab,
              let textSystem = originController.editorStore.existingSystem(for: activeTab.id.uuidString)
        else { return }

        let (line, column) = Self.parse(input)
        // `textSystem.text` materializes the whole document, which this
        // codebase avoids on every-keystroke paths (`EditorTextSystem+LineIndex.swift`)
        // — but Go to Line is a rare, one-shot user action, not a hot path,
        // so the §11 no-copy discipline does not apply here.
        let text = textSystem.text as NSString
        let offset = textSystem.lineIndex.utf16Offset(forLine: line, column: column ?? 1, in: text)
        textSystem.revealSelection(utf16Range: NSRange(location: offset, length: 0), flash: true, animated: true)
    }

    /// Parses `"line[:column]"`. A missing or non-numeric line defaults to
    /// line 1 rather than rejecting the input outright — Go to Line is a
    /// quick, low-stakes action, and this codebase's own `EditorLineIndex`
    /// convention throughout is to clamp rather than error on out-of-range
    /// input. `omittingEmptySubsequences: false` matters for a leading colon
    /// (`":3"`): omitting empty subsequences (the default) would drop the
    /// empty line component entirely, shifting "3" into the line position
    /// and silently jumping to line 3 instead of column 3 on the current
    /// line 1 (hostile review finding, PR #126).
    private static func parse(_ input: String) -> (line: Int, column: Int?) {
        let parts = input.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        let line = parts.first.flatMap { Int($0) } ?? 1
        let column = parts.count > 1 ? Int(parts[1]) : nil
        return (line, column)
    }

    func windowWillClose(_: Notification) {
        coordinator?.goToLinePanelDidClose(self)
    }
}
