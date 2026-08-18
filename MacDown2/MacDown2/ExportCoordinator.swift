import AppKit
import ExportService
import FileCore
import Foundation
import SwiftUI
import Themes
import UniformTypeIdentifiers
import Workspace

/// Orchestrates export for the active document: reads the live editor snapshot,
/// presents the export panel (save location + options), composes the export
/// off the main actor, and surfaces the result or the error.
@MainActor
final class ExportCoordinator {
    private let coordinator: WindowCoordinator
    private let themeController: ThemeController

    init(coordinator: WindowCoordinator, themeController: ThemeController) {
        self.coordinator = coordinator
        self.themeController = themeController
    }

    /// Whether the key window's active document is exportable Markdown.
    var canExportActiveDocument: Bool {
        coordinator.keyModel?.activeDocument?.format.id == "markdown"
    }

    /// Presents the export panel and performs the requested export.
    func exportActiveDocument() async {
        guard let model = coordinator.keyModel, let document = model.activeDocument else { return }
        guard document.format.id == "markdown" else { return }

        let baseName = document.fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
        let directory = document.fileURL?.deletingLastPathComponent()

        guard let selection = await presentExportPanel(defaultName: baseName, directory: directory) else {
            return
        }

        do {
            let files = try await performExport(document: document, selection: selection)
            reveal(files)
        } catch {
            presentError(error)
        }
    }

    // MARK: - Panel

    /// The resolved export choices: the save destination plus the panel's
    /// format and style options.
    private struct ExportSelection {
        let url: URL
        let format: ExportFormatOption
        let style: ExportStyleEmbedding
    }

    private func presentExportPanel(
        defaultName: String,
        directory: URL?
    ) async -> ExportSelection? {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowedContentTypes = [.html, .pdf]
        panel.nameFieldStringValue = defaultName + ".html"
        if let directory {
            panel.directoryURL = directory
        }

        let selectionModel = ExportSelectionModel()
        panel.accessoryView = NSHostingView(rootView: ExportPanelView(model: selectionModel))

        let url = await withCheckedContinuation { continuation in
            if let window = NSApp.keyWindow {
                panel.beginSheetModal(for: window) { result in
                    continuation.resume(returning: result == .OK ? panel.url : nil)
                }
            } else {
                continuation.resume(returning: panel.runModal() == .OK ? panel.url : nil)
            }
        }

        guard let url else { return nil }
        return ExportSelection(url: url, format: selectionModel.format, style: selectionModel.style)
    }

    // MARK: - Execution

    private func performExport(
        document: FileCore.FileDocument,
        selection: ExportSelection
    ) async throws -> [URL] {
        let request = ExportRequest(
            text: document.text,
            sourceGeneration: document.mutationGeneration,
            theme: themeController.current,
            documentDirectory: document.fileURL?.deletingLastPathComponent()
        )

        switch selection.format {
        case .standaloneHTML:
            let target = ExportTarget.html(url: selection.url, mode: .standalone(style: selection.style))
            let result = try await ExportService.exportHTML(request, to: target)
            return [result.primaryFile] + result.companionFiles
        case .selfContainedHTML:
            let target = ExportTarget.html(url: selection.url, mode: .selfContained)
            let result = try await ExportService.exportHTML(request, to: target)
            return [result.primaryFile] + result.companionFiles
        case .pdf:
            let target = ExportTarget.pdf(url: selection.url)
            let prepared = try await ExportService.prepare(request, target: target)
            try await PDFExportAdapter.export(prepared, to: selection.url)
            return [selection.url]
        }
    }

    // MARK: - Feedback

    private func reveal(_ files: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(files)
    }

    private func presentError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Export Failed"
        alert.informativeText = error.localizedDescription
        if let window = NSApp.keyWindow {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}
