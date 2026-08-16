import AppKit
import CoreTransferable
import FileTree
import JSONSupport
import OutlineUI
import SwiftUI
import UniformTypeIdentifiers
import Workspace

struct SidebarView: View {
    @Bindable var model: WorkspaceModel
    @Bindable var outlineController: OutlineController
    @Bindable var fileTreeModel: FileTreeModel
    @Environment(\.windowCoordinator) var coordinator

    @FocusState private var outlineFocused: Bool

    var body: some View {
        List(selection: sidebarSelection) {
            ForEach(model.sectionOrder) { section in
                Section {
                    DisclosureGroup(
                        isExpanded: Binding(
                            get: { model.isSectionExpanded(section) },
                            set: { model.setSectionExpanded(section, $0) }
                        )
                    ) {
                        content(for: section)
                    } label: {
                        sectionLabel(for: section)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        .focused($outlineFocused)
        .onChange(of: outlineController.focusRequestID) { _, _ in
            outlineFocused = true
            // FocusState is applied by SwiftUI on the next update pass. Wait
            // for that pass before invalidating command validation so the
            // formatting menu observes the actual first responder, not the
            // pre-focus state.
            Task { @MainActor in
                await Task.yield()
                coordinator?.commandStateDidChange()
            }
        }
        .onKeyPress(.return) {
            if let url = fileTreeModel.selectedURL {
                activateFileTreeURL(url)
            } else if isJSON, let jsonSelected = outlineController.jsonSelectedItemID {
                outlineController.activateJSON(jsonSelected)
            } else if let selectedItemID = outlineController.selectedItemID {
                outlineController.activate(selectedItemID)
            } else {
                return .ignored
            }
            return .handled
        }
        .alert(
            "Folder Operation Failed",
            isPresented: Binding(
                get: { fileTreeModel.lastOperationError != nil },
                set: {
                    if !$0 {
                        fileTreeModel.clearOperationError()
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) { fileTreeModel.clearOperationError() }
        } message: {
            Text(fileTreeModel.lastOperationError?.localizedDescription ?? "Unknown error")
        }
    }

    private var sidebarSelection: Binding<SidebarSelection?> {
        Binding(
            get: {
                if let url = fileTreeModel.selectedURL {
                    return .file(url)
                }
                if isJSON {
                    return outlineController.jsonSelectedItemID.map(SidebarSelection.jsonOutline)
                }
                return outlineController.selectedItemID.map(SidebarSelection.outline)
            },
            set: { selection in
                switch selection {
                case let .file(url):
                    fileTreeModel.selectedURL = url
                    outlineController.selectedItemID = nil
                    outlineController.jsonSelectedItemID = nil
                case let .outline(id):
                    outlineController.selectedItemID = id
                    outlineController.jsonSelectedItemID = nil
                    fileTreeModel.selectedURL = nil
                case let .jsonOutline(id):
                    outlineController.jsonSelectedItemID = id
                    outlineController.selectedItemID = nil
                    fileTreeModel.selectedURL = nil
                case nil:
                    fileTreeModel.selectedURL = nil
                    outlineController.selectedItemID = nil
                    outlineController.jsonSelectedItemID = nil
                }
            }
        )
    }

    /// Section header with explicit reorder controls (acceptance box 4:
    /// "user-rearrangeable").
    ///
    /// `List`'s native `.onMove` drag reordering is documented for a
    /// `ForEach` of plain rows; applied to a `ForEach` producing `Section`s
    /// (as this sidebar needs, to keep each section collapsible) it does not
    /// reliably reorder — confirmed interactively: dragging shows the
    /// insertion-line affordance but the drop does not apply. Rather than
    /// depend on that undefined behavior, reordering is an explicit,
    /// always-visible control — arguably more discoverable than an
    /// undiscoverable drag besides.
    private func sectionLabel(for section: SidebarSection) -> some View {
        HStack {
            Label(section.title, systemImage: section.systemImage)
            Spacer()
            if let index = model.sectionOrder.firstIndex(of: section) {
                HStack(spacing: 8) {
                    Button {
                        moveSection(at: index, up: true)
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .disabled(index == 0)
                    .help("Move \(section.title) Up")

                    Button {
                        moveSection(at: index, up: false)
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .disabled(index == model.sectionOrder.count - 1)
                    .help("Move \(section.title) Down")
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("moveSection-\(section.rawValue)")
            }
        }
        .accessibilityIdentifier(section == .folder ? "folderSection" : "outlineSection")
    }

    /// Mirrors the `ForEach.onMove` offset convention `Workspace.reorder`
    /// implements: `toOffset` is an insertion point in the pre-move ordering.
    /// Moving `index` up by one is "insert before `index - 1`"; moving it
    /// down by one is "insert before `index + 2`" (past both itself and its
    /// neighbor in the pre-move list).
    private func moveSection(at index: Int, up movingUp: Bool) {
        let destination = movingUp ? index - 1 : index + 2
        model.moveSections(fromOffsets: IndexSet(integer: index), toOffset: destination)
    }

    @ViewBuilder
    private func content(for section: SidebarSection) -> some View {
        switch section {
        case .folder:
            folderContent
        case .outline:
            outlineContent
                .accessibilityIdentifier("outlineSection")
        }
    }

    @ViewBuilder
    private var outlineContent: some View {
        if isJSON {
            jsonOutlineContent
        } else {
            markdownOutlineContent
        }
    }

    /// E11: the JSON document outline — the format-neutral channel. Invalid
    /// JSON shows the parser's diagnostic instead of a stale tree.
    @ViewBuilder
    private var jsonOutlineContent: some View {
        switch outlineController.jsonAvailability {
        case .notParsed:
            EmptyView()
        case .invalidJSON:
            VStack(alignment: .leading, spacing: 4) {
                Label("Invalid JSON", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                if let diagnostic = outlineController.jsonDiagnostic {
                    Text("Line \(diagnostic.line), column \(diagnostic.column): \(diagnostic.message)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        case .ready:
            let rows = JSONOutlineBuilder.visibleRows(
                outlineController.jsonItems,
                collapsed: outlineController.jsonCollapsedItemIDs
            )
            ForEach(rows) { row in
                JSONOutlineRowView(item: row.item, depth: row.depth, outlineController: outlineController)
                    .tag(SidebarSelection.jsonOutline(row.item.id))
                    .accessibilityIdentifier("jsonOutlineRow-\(row.item.id)")
            }
        case .unsupportedFormat, .noHeadings:
            EmptyView()
        }
    }

    /// The Markdown heading outline (D8, unchanged by E11).
    @ViewBuilder
    private var markdownOutlineContent: some View {
        switch outlineController.availability {
        case .notParsed:
            EmptyView()
        case let .unsupportedFormat(formatName):
            Text("No outline available for \(formatName)")
                .foregroundStyle(.secondary)
        case .noHeadings:
            Text("No headings")
                .foregroundStyle(.secondary)
        case .invalidJSON:
            // Only the JSON channel produces this; unreachable for Markdown.
            EmptyView()
        case .ready:
            // Collapse-aware flattening and depth both come from the module,
            // so what renders here is exactly what `OutlineTreeTests` covers.
            let rows = OutlineTree.visibleRows(
                outlineController.items,
                collapsed: outlineController.collapsedItemIDs
            )
            ForEach(rows) { row in
                OutlineRowView(item: row.item, depth: row.depth, outlineController: outlineController)
                    .tag(SidebarSelection.outline(row.item.id))
                    .accessibilityIdentifier("outlineRow-\(row.item.id)")
            }
        }
    }

    private var isJSON: Bool {
        model.activeDocument?.format.id == "json"
    }

    func activateFileTreeURL(_ url: URL) {
        guard let row = fileTreeModel.rows.first(where: { $0.id == url }) else { return }
        if row.entry.isDirectory, !row.entry.isPackage {
            Task { await fileTreeModel.toggleExpansion(url) }
        } else {
            Task {
                await coordinator?.openDocument(
                    at: url,
                    folderRoot: fileTreeModel.root,
                    folderAccessURL: fileTreeModel.rootAccessURL
                )
            }
        }
    }
}
