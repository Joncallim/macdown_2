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
///
/// It is a value type with no stored state of its own: the window coordinator
/// hands one out per menu evaluation, and nothing must survive between them.
@MainActor
struct ExportCoordinator {
    private let coordinator: WindowCoordinator
    private let themeController: ThemeController

    init(coordinator: WindowCoordinator, themeController: ThemeController) {
        self.coordinator = coordinator
        self.themeController = themeController
    }

    /// How many warnings one alert lists before it summarises the rest.
    private let warningsShownAtMost = 6

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
            let result = try await performExport(document: document, selection: selection)
            // Warnings are read before Finder takes focus, so the report is not
            // left sitting behind another app's window.
            await presentWarningsIfNeeded(result.diagnostics)
            reveal(result.primaryFile)
        } catch is CancellationError {
            // The user withdrew the export; there is nothing to report.
        } catch {
            await presentError(error)
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
        panel.prompt = "Export"
        panel.message = "Choose where to export this document."
        if let directory {
            panel.directoryURL = directory
        }

        let selectionModel = ExportSelectionModel()
        Self.apply(selectionModel.format, to: panel, defaultBaseName: defaultName)

        let panelView = ExportPanelView(model: selectionModel) { [weak panel] format in
            guard let panel else { return }
            Self.apply(format, to: panel, defaultBaseName: defaultName)
        }
        let accessory = NSHostingView(rootView: panelView)
        // An NSSavePanel accessory is laid out from its frame, so the hosting
        // view is sized before it is attached rather than collapsing to zero.
        accessory.frame = NSRect(origin: .zero, size: accessory.fittingSize)
        panel.accessoryView = accessory

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

    /// Keeps the panel's filename and enforced content type in step with the
    /// chosen format, so picking PDF cannot save a PDF named `.html`.
    private static func apply(_ format: ExportFormatOption, to panel: NSSavePanel, defaultBaseName: String) {
        panel.allowedContentTypes = [format.contentType]

        let typed = panel.nameFieldStringValue
        var base = typed.isEmpty ? defaultBaseName : typed
        // Only an extension this panel could have written is replaced; a name
        // like "Report v1.2" keeps every character the user typed.
        for known in ExportFormatOption.knownExtensions where base.lowercased().hasSuffix(".\(known)") {
            base = String(base.dropLast(known.count + 1))
            break
        }
        if base.isEmpty {
            base = defaultBaseName
        }
        panel.nameFieldStringValue = "\(base).\(format.fileExtension)"
    }

    // MARK: - Execution

    private struct ExportOutcome {
        let primaryFile: URL
        let diagnostics: [ExportDiagnostic]
    }

    private func performExport(
        document: FileCore.FileDocument,
        selection: ExportSelection
    ) async throws -> ExportOutcome {
        let request = ExportRequest(
            text: document.text,
            sourceGeneration: document.mutationGeneration,
            theme: themeController.current,
            documentURL: document.fileURL
        )

        switch selection.format {
        case .standaloneHTML, .selfContainedHTML:
            let mode: HTMLExportMode = selection.format == .selfContainedHTML
                ? .selfContained
                : .standalone(style: selection.style)
            let result = try await ExportService.exportHTML(request, to: .html(url: selection.url, mode: mode))
            return ExportOutcome(primaryFile: result.primaryFile, diagnostics: result.diagnostics)
        case .pdf:
            let prepared = try await ExportService.prepare(request, target: .pdf(url: selection.url))
            try await PDFExportAdapter.export(prepared, to: selection.url)
            return ExportOutcome(primaryFile: selection.url, diagnostics: prepared.diagnostics)
        }
    }

    // MARK: - Feedback

    /// Selects the exported document in Finder. Companion files are deliberately
    /// not selected: an image-heavy export would otherwise open Finder with two
    /// dozen items highlighted across two folders.
    private func reveal(_ file: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([file])
    }

    /// Composition warnings are reported, never dropped: an export that quietly
    /// left images unresolved would look successful and open broken.
    private func presentWarningsIfNeeded(_ diagnostics: [ExportDiagnostic]) async {
        let warnings = diagnostics.filter { $0.severity == .warning }
        guard !warnings.isEmpty else { return }

        let shown = warnings.prefix(warningsShownAtMost).map(\.message)
        var text = shown.joined(separator: "\n")
        if warnings.count > shown.count {
            text += "\n…and \(warnings.count - shown.count) more."
        }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = warnings.count == 1
            ? "Exported with 1 warning"
            : "Exported with \(warnings.count) warnings"
        alert.informativeText = text
        await present(alert)
    }

    private func presentError(_ error: Error) async {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Export Failed"
        alert.informativeText = error.localizedDescription
        if let suggestion = (error as? LocalizedError)?.recoverySuggestion {
            alert.informativeText += "\n\n" + suggestion
        }
        await present(alert)
    }

    private func present(_ alert: NSAlert) async {
        guard let window = NSApp.keyWindow else {
            alert.runModal()
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            alert.beginSheetModal(for: window) { _ in
                continuation.resume()
            }
        }
    }
}
