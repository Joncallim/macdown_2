import AppKit
import AppSettings
import Contributions
import ExportService
import FileCore
import Foundation
import MarkdownEngine
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
    private let appSettings: AppSettingsModel

    init(coordinator: WindowCoordinator, themeController: ThemeController, appSettings: AppSettingsModel) {
        self.coordinator = coordinator
        self.themeController = themeController
        self.appSettings = appSettings
    }

    /// How many diagnostics one alert lists before it summarises the rest.
    private let diagnosticsShownAtMost = 6

    /// Whether the key window's active document is exportable Markdown and
    /// does not already have an export in flight.
    var canExportActiveDocument: Bool {
        guard let model = coordinator.keyModel, model.activeDocument?.format.id == "markdown" else {
            return false
        }
        return !coordinator.isExporting(model)
    }

    /// Presents the export panel and performs the requested export.
    ///
    /// Re-entrancy guard: two ⌘⇧E while a save panel or a slow PDF render is
    /// still in flight must not start two exports of the same document
    /// racing the same destination file. Scoped to `model` (one per window),
    /// set for the whole call including panel presentation — cancelling the
    /// panel already exits through the same `defer`.
    func exportActiveDocument() async {
        guard let model = coordinator.keyModel, let document = model.activeDocument else { return }
        guard document.format.id == "markdown" else { return }
        guard !coordinator.isExporting(model) else { return }

        coordinator.setExporting(true, for: model)
        defer { coordinator.setExporting(false, for: model) }

        let baseName = document.fileURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
        let directory = document.fileURL?.deletingLastPathComponent()

        guard let selection = await presentExportPanel(defaultName: baseName, directory: directory) else {
            return
        }

        do {
            let result = try await performExport(document: document, selection: selection)
            // Diagnostics are read before Finder takes focus, so the report is
            // not left sitting behind another app's window.
            await presentDiagnosticsIfNeeded(result.diagnostics)
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

        let selectionModel = ExportSelectionModel(
            format: Self.exportFormatOption(from: appSettings.previewExport.defaultExportFormat),
            style: Self.exportStyleEmbedding(from: appSettings.previewExport.defaultExportStyle)
        )
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

    /// Seeds the panel's initial choice only — the panel itself remains fully
    /// user-editable per export. Does not touch `ExportRequest`/
    /// `ExportComposer`, whose template/layout/resource-root/budget/
    /// metadata-policy are fixed by the composer regardless of preferences
    /// (epic-13-implementation.md §4, invariant 4).
    static func exportFormatOption(
        from preference: PreviewExportSettings.DefaultExportFormat
    ) -> ExportFormatOption {
        switch preference {
        case .standaloneHTML: .standaloneHTML
        case .selfContainedHTML: .selfContainedHTML
        case .pdf: .pdf
        }
    }

    static func exportStyleEmbedding(
        from preference: PreviewExportSettings.DefaultExportStyle
    ) -> ExportStyleEmbedding {
        switch preference {
        case .embedded: .embedded
        case .linked: .linked
        }
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
        let adaptation = try await exportContributionAdaptation(for: document)
        let request = ExportRequest(
            text: document.text,
            sourceGeneration: document.mutationGeneration,
            theme: themeController.current,
            documentURL: document.fileURL,
            contributions: adaptation.contributions
        )

        switch selection.format {
        case .standaloneHTML, .selfContainedHTML:
            let mode: HTMLExportMode = selection.format == .selfContainedHTML
                ? .selfContained
                : .standalone(style: selection.style)
            let result = try await ExportService.exportHTML(request, to: .html(url: selection.url, mode: mode))
            return ExportOutcome(
                primaryFile: result.primaryFile,
                diagnostics: Self.combinedDiagnostics(adaptation, result.diagnostics)
            )
        case .pdf:
            let prepared = try await ExportService.prepare(request, target: .pdf(url: selection.url))
            try await PDFExportAdapter.export(prepared, to: selection.url)
            return ExportOutcome(
                primaryFile: selection.url,
                diagnostics: Self.combinedDiagnostics(adaptation, prepared.diagnostics)
            )
        }
    }

    /// Standalone (anchorless) diagnostics first, then the export service's
    /// own — the exact same order for both the HTML and PDF paths above, so
    /// the two cannot drift through independently copy-pasted merge logic
    /// (architecture takeover, pass 9/10).
    nonisolated static func combinedDiagnostics(
        _ adaptation: ExportContributionAdapter.Adaptation,
        _ serviceDiagnostics: [ExportDiagnostic]
    ) -> [ExportDiagnostic] {
        adaptation.standaloneDiagnostics + serviceDiagnostics
    }

    /// Computes contribution placements for `document` via a fresh parse,
    /// independent of whatever Preview's own parse session is doing for the
    /// same document at the same moment — matching how
    /// `ExportComposer.prepare` already parses `request.text` independently
    /// of Preview, today, before this epic (epic-14-implementation.md §7.1).
    /// One extra parse per export, accepted as proportionally negligible
    /// next to export's other costs (§1 risk 2, §11).
    private func exportContributionAdaptation(
        for document: FileCore.FileDocument
    ) async throws -> ExportContributionAdapter.Adaptation {
        let revision = Int(exactly: document.mutationGeneration) ?? Int.max
        let parsed = try await ParseEngine().parse(document.text, revision: revision)
        let results = try await ContributionRegistry.standard.run(
            document: parsed, sourceText: document.text, sourceGeneration: document.mutationGeneration
        )
        return ExportContributionAdapter.adapt(results)
    }

    // MARK: - Feedback

    /// Selects the exported document in Finder. Companion files are deliberately
    /// not selected: an image-heavy export would otherwise open Finder with two
    /// dozen items highlighted across two folders.
    private func reveal(_ file: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([file])
    }

    /// Composition diagnostics are reported, never dropped: an export that
    /// quietly left images unresolved, or a derived contribution broken, would
    /// look successful and open wrong. This runs only after a successful
    /// export, so an `.error` diagnostic here means one part of the document
    /// did not resolve, not that the export failed — resolution failures that
    /// are fatal to the export itself are thrown from `performExport` and never
    /// reach this point.
    private func presentDiagnosticsIfNeeded(_ diagnostics: [ExportDiagnostic]) async {
        guard !diagnostics.isEmpty else { return }

        let shown = diagnostics.prefix(diagnosticsShownAtMost).map(\.message)
        var text = shown.joined(separator: "\n")
        if diagnostics.count > shown.count {
            text += "\n…and \(diagnostics.count - shown.count) more."
        }

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = diagnostics.count == 1
            ? "Exported with 1 issue"
            : "Exported with \(diagnostics.count) issues"
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
