import AppKit
import EditorCore
import FileCore
import Highlighting
import JSONSupport
import MarkdownEngine
import OutlineUI
import Preview
import SwiftUI
import Themes
import Workspace

struct ContentAreaView: View {
    let model: WorkspaceModel
    let editorStore: EditorTextSystemStore
    let highlightStore: SyntaxHighlightStore
    let parseStore: MarkdownParseStore
    let jsonAnalysisStore: JSONAnalysisStore
    let themeController: ThemeController
    let outlineController: OutlineController
    let externalFileController: ExternalFileController

    @State private var scrollController = ScrollSyncController()

    var body: some View {
        content(
            for: model.activeDocument,
            tab: model.tabStore.activeTab,
            identity: activeIdentity
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func content(
        for document: FileCore.FileDocument?,
        tab: WorkspaceTab?,
        identity: String?
    ) -> some View {
        if let document, let tab, let identity {
            documentContent(document, tab: tab, identity: identity)
        } else {
            emptyState
        }
    }

    private var activeIdentity: String? {
        model.tabStore.activeTabID?.uuidString
    }

    private var textBinding: Binding<String> {
        Binding(
            get: { model.activeDocument?.text ?? "" },
            set: { newText in
                model.tabStore.updateActiveDocument { $0.edited(text: newText) }
            }
        )
    }

    private func documentContent(
        _ document: FileCore.FileDocument,
        tab: WorkspaceTab,
        identity: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header bar
            HStack(spacing: 10) {
                Image(systemName: documentIcon(for: document.format.id))
                    .foregroundStyle(.secondary)

                Text(title(for: document))
                    .font(.system(size: 13, weight: .semibold))

                if document.fileURL == nil {
                    Text("— Save As… ⌘⇧S to name this document")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                // Format badge
                Text(document.format.name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)

            ExternalFileStatusView(controller: externalFileController)
            WorkspaceRecoveryRequiredNotice(model: model)

            Divider()

            // Source / preview split
            DocumentEditorSplitView(
                model: model,
                document: document,
                tab: tab,
                identity: identity,
                text: textBinding,
                editorStore: editorStore,
                highlightStore: highlightStore,
                parseStore: parseStore,
                jsonAnalysisStore: jsonAnalysisStore,
                themeController: themeController,
                scrollController: scrollController,
                outlineController: outlineController
            )
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.quaternary)

            Text("No Document")
                .font(.title2)
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                ShortcutHint(shortcut: "⌘N", label: "New File")
                ShortcutHint(shortcut: "⌘O", label: "Open File")
            }
        }
    }

    private func title(for document: FileCore.FileDocument) -> String {
        document.fileURL?.lastPathComponent ?? "Untitled"
    }

    private func documentIcon(for formatID: String) -> String {
        let sourceIcons: Set = [
            "javascript", "typescript", "python", "ruby",
            "swift", "c", "bash", "sql",
        ]
        if sourceIcons.contains(formatID) {
            return "chevron.left.forwardslash.chevron.right"
        }
        switch formatID {
        // `doc.richtext`, not `richtext` — the latter is not an SF Symbol and
        // logged "No symbol named 'richtext' found in system symbol set" on
        // every header render, which is what filled the console with errors.
        case "markdown": return "doc.richtext"
        case "html": return "chevron.left.forwardslash.chevron.right"
        case "json": return "curlybraces"
        default: return "doc.text"
        }
    }
}

private struct WorkspaceRecoveryRequiredNotice: View {
    let model: WorkspaceModel

    var body: some View {
        if case let .conditionalPublicationRecoveryRequired(url) = model.lastError {
            HStack(spacing: 10) {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .foregroundStyle(.orange)
                Text(
                    "A competing version was preserved as \(url.lastPathComponent). "
                        + "Reveal it, then use Save As to keep this copy."
                )
                .font(.callout)
                Spacer()
                Button("Reveal") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                .accessibilityIdentifier("conditionalPublicationRevealButton")
                Button("Save As…") {
                    Task { await model.saveAs() }
                }
                .accessibilityIdentifier("conditionalPublicationSaveAsButton")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(.orange.opacity(0.15))
            .accessibilityIdentifier("conditionalPublicationRecoveryNotice")
        } else if case let .recoveryCleanupRequired(url) = model.lastError {
            HStack(spacing: 10) {
                Image(systemName: "externaldrive.badge.exclamationmark")
                    .foregroundStyle(.orange)
                Text(
                    "Recovery cleanup for \(url.lastPathComponent) needs attention. "
                        + "Reveal it, retry, or use Save As."
                )
                .font(.callout)
                Spacer()
                Button("Reveal") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                .accessibilityIdentifier("recoveryCleanupRevealButton")
                Button("Retry") {
                    Task { await model.retryRecoveryCleanup() }
                }
                .accessibilityIdentifier("recoveryCleanupRetryButton")
                Button("Save As…") {
                    Task { await model.saveAs() }
                }
                .accessibilityIdentifier("recoveryCleanupSaveAsButton")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(.orange.opacity(0.15))
            .accessibilityIdentifier("recoveryCleanupRequiredNotice")
        }
    }
}

// MARK: - Helpers

private struct ShortcutHint: View {
    let shortcut: String
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Text(shortcut)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
            Text(label)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}
