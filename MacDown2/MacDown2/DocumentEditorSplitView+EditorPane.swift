import EditorCore
import SwiftUI

/// The editor pane and its status bar (epic-22-implementation.md §6.7, §17
/// Slice 2b). Split out of `DocumentEditorSplitView.swift` to stay under the
/// type-body-length/file-length lint budgets, matching
/// `DocumentEditorSplitView+Divider.swift`'s same reason — `editorConfiguration`,
/// `parseSession`, `appSettings`, and `statusBarSelection` are internal (not
/// `private`) in the main file for that reason.
extension DocumentEditorSplitView {
    var editorPane: some View {
        VStack(spacing: 0) {
            EditorView(
                text: $text,
                identity: identity,
                configuration: editorConfiguration,
                store: editorStore,
                onSelectionChange: { range in
                    statusBarSelection = range
                    outlineController.referenceOffsetDidChange(range.location)
                    outlineController.jsonReferenceOffsetDidChange(range.location)
                },
                onScrollChange: { offset in
                    handleEditorScroll(utf16Offset: offset)
                    outlineController.jsonReferenceOffsetDidChange(offset)
                }
            )
            .accessibilityIdentifier("editorPane")
            .task(id: identity) {
                attachHighlighter()
            }

            // `system.text`/`system.lineIndex` are read together from the SAME
            // live `EditorTextSystem`, not from the `text` SwiftUI binding:
            // the binding is only as current as the last SwiftUI render pass,
            // while `system.lineIndex` reflects the text system's real,
            // synchronous state. Mixing the two crashed
            // `EditorLineIndex.column(atUTF16Offset:onLine:in:)` with an
            // out-of-bounds substring range the moment a filter or other
            // programmatic edit changed the text system faster than SwiftUI
            // re-rendered `text` (found by `TextFilterCoordinatorTests`'
            // real, mounted-window integration test).
            if appSettings?.editor.showsStatusBar != false,
               let system = editorStore.existingSystem(for: identity) {
                EditorStatusBarView(
                    text: system.text,
                    selectedRange: statusBarSelection,
                    lineIndex: system.lineIndex,
                    indentationWidth: appSettings?.editor.indentationWidth ?? 4,
                    convertsTabsToSpaces: appSettings?.editor.convertsTabsToSpaces ?? true,
                    onGoToLine: { coordinator?.toggleGoToLine() }
                )
            }
        }
    }

    /// Forwards the editor's visible top line into the scroll-sync
    /// controller so the preview follows. `utf16Offset` comes from
    /// `EditorView`'s scroll callback (see `EditorTextSystem.topVisibleUTF16Offset`).
    ///
    /// Skips the outline update while `scrollController.isJumping`: an
    /// animated `revealSelection` (the outline's own jump) fires this
    /// callback once per frame of its ~0.2s scroll animation, and those
    /// mid-flight offsets don't yet reflect the jump's target — reading them
    /// back into the outline overwrote the correct highlight (already set
    /// synchronously by the jump's own selection change, below in
    /// `pendingJumpLineRange`) with a stale one, leaving the *previous*
    /// heading bolded after a jump landed correctly.
    func handleEditorScroll(utf16Offset: Int) {
        guard let sourceMap = parseSession.document?.sourceMap else { return }
        scrollController.editorDidScroll(toLine: sourceMap.line(atUTF16Offset: utf16Offset))
        guard !scrollController.isJumping else { return }
        outlineController.referenceOffsetDidChange(utf16Offset)
    }

    func attachHighlighter() {
        guard let textSystem = editorStore.existingSystem(for: identity) else { return }
        _ = highlightStore.highlighter(
            for: identity,
            textSystem: textSystem,
            languageID: document.format.highlightLanguageID,
            theme: themeController.current
        )
    }
}
