import OutlineUI
import SwiftUI
import Workspace

struct SidebarView: View {
    @Bindable var model: WorkspaceModel
    @Bindable var outlineController: OutlineController

    @FocusState private var outlineFocused: Bool

    var body: some View {
        List(selection: $outlineController.selectedItemID) {
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
                        Label(section.title, systemImage: section.systemImage)
                    }
                }
            }
            .onMove { offsets, offset in
                model.moveSections(fromOffsets: offsets, toOffset: offset)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 180, ideal: 220)
        .focused($outlineFocused)
        .onChange(of: outlineController.focusRequestID) { _, _ in
            outlineFocused = true
        }
        .onKeyPress(.return) {
            guard let selectedItemID = outlineController.selectedItemID else { return .ignored }
            outlineController.activate(selectedItemID)
            return .handled
        }
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
    private var folderContent: some View {
        if let folderURL = model.folderURL {
            Text(folderURL.lastPathComponent)
                .lineLimit(1)
        } else {
            Text("No folder opened")
                .foregroundStyle(.secondary)
        }
    }

    /// Flat, depth-annotated traversal of the visible tree (D6/D3: indent by
    /// tree position, never by `level`). `OutlineTree.visibleItems` already
    /// does the collapse-aware flattening; depth is display-only, so it's
    /// tracked here rather than in the headless-testable `OutlineUI` module.
    private var visibleRows: [(item: OutlineItem, depth: Int)] {
        var result: [(item: OutlineItem, depth: Int)] = []
        func visit(_ items: [OutlineItem], depth: Int) {
            for item in items {
                result.append((item, depth))
                if !outlineController.collapsedItemIDs.contains(item.id) {
                    visit(item.children, depth: depth + 1)
                }
            }
        }
        visit(outlineController.items, depth: 0)
        return result
    }

    @ViewBuilder
    private var outlineContent: some View {
        switch outlineController.availability {
        case .notParsed:
            EmptyView()
        case let .unsupportedFormat(formatName):
            Text("No outline available for \(formatName)")
                .foregroundStyle(.secondary)
        case .noHeadings:
            Text("No headings")
                .foregroundStyle(.secondary)
        case .ready:
            ForEach(visibleRows, id: \.item.id) { row in
                OutlineRowView(item: row.item, depth: row.depth, outlineController: outlineController)
                    .tag(row.item.id)
                    .accessibilityIdentifier("outlineRow-\(row.item.id)")
            }
        }
    }
}

/// One outline row: a disclosure chevron (only for nodes with children),
/// title text, and current-section tint (D6 — a distinct visual channel from
/// `List` selection, never bound to it).
private struct OutlineRowView: View {
    let item: OutlineItem
    let depth: Int
    @Bindable var outlineController: OutlineController

    var body: some View {
        HStack(spacing: 4) {
            if item.children.isEmpty {
                Color.clear.frame(width: 12, height: 12)
            } else {
                Button(action: toggleCollapsed) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .frame(width: 12, height: 12)
                }
                .buttonStyle(.plain)
            }

            Text(item.title.isEmpty ? "Untitled section" : item.title)
                .fontWeight(isCurrent ? .semibold : .regular)
                .foregroundStyle(item.title
                    .isEmpty ? AnyShapeStyle(.tertiary) :
                    (isCurrent ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary)))
                .lineLimit(1)
        }
        .padding(.leading, CGFloat(depth) * 14)
        .contentShape(Rectangle())
        .onTapGesture {
            outlineController.activate(item.id)
        }
    }

    private var isCollapsed: Bool {
        outlineController.collapsedItemIDs.contains(item.id)
    }

    private var isCurrent: Bool {
        outlineController.currentItemID == item.id
    }

    private func toggleCollapsed() {
        if isCollapsed {
            outlineController.collapsedItemIDs.remove(item.id)
        } else {
            outlineController.collapsedItemIDs.insert(item.id)
        }
    }
}

private extension SidebarSection {
    var title: String {
        switch self {
        case .folder: "Folder"
        case .outline: "Outline"
        }
    }

    var systemImage: String {
        switch self {
        case .folder: "folder"
        case .outline: "list.bullet"
        }
    }
}
