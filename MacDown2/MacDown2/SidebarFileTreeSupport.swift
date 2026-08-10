import AppKit
import CoreTransferable
import FileTree
import OutlineUI
import SwiftUI
import UniformTypeIdentifiers
import Workspace

struct FileTreeRowView: View {
    let row: FileTreeRow
    @Bindable var model: FileTreeModel
    let activate: (URL) -> Void
    let didRename: (URL, URL) -> Void
    let didMove: (URL, URL) -> Void
    let didDelete: (URL) -> Void
    let didCreate: (URL, Bool, FileTreeOperationContext) -> Void
    @State private var newName = ""
    @FocusState private var renameFocused: Bool

    var body: some View {
        HStack(spacing: 4) {
            if row.entry.isDirectory, !row.entry.isPackage {
                Button { Task { await model.toggleExpansion(row.entry.url) } } label: {
                    Image(systemName: row.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold)).frame(width: 12, height: 12)
                }.buttonStyle(.plain)
            } else {
                Color.clear.frame(width: 12, height: 12)
            }
            Image(nsImage: NSWorkspace.shared.icon(forFile: row.entry.url.path)).resizable().frame(
                width: 16,
                height: 16
            )
            if model.renamingURL == row.entry.url {
                TextField("Name", text: $newName, onCommit: commitRename)
                    .focused($renameFocused)
                    .accessibilityIdentifier("fileTreeRenameField")
                    .onAppear { newName = row.entry.name; renameFocused = true }
                    .onChange(of: renameFocused) { _, focused in
                        if !focused {
                            commitRename()
                        }
                    }
                    .onExitCommand { model.renamingURL = nil }
            } else {
                Text(row.entry.name).lineLimit(1)
            }
            if row.isLoading {
                ProgressView().controlSize(.small)
            }
            if let loadError = row.loadError {
                Button {
                    Task { await model.expand(row.entry.url) }
                } label: {
                    Image(systemName: "exclamationmark.triangle")
                }
                .buttonStyle(.plain)
                .help("Could not load folder: \(loadError). Retry")
                .accessibilityLabel("Retry loading \(row.entry.name)")
            }
        }
        .padding(.leading, CGFloat(row.depth) * 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture(count: model.preferences.opensOnSingleClick ? 1 : 2).onEnded {
                if !row.entry.isDirectory || row.entry.isPackage {
                    activate(row.entry.url)
                }
            }
        )
        .draggable(FileTreeInternalDrag.issue(url: row.entry.url, from: model))
        .dropDestination(for: FileTreeInternalDrag.self, action: { items, _ in
            guard !row.entry.isPackage else { return false }
            let destination = destinationDirectory
            let context = model.beginOperation()
            Task {
                for item in items where item.url != destination {
                    do {
                        guard let source = FileTreeInternalDrag.trustedURL(from: item, for: model) else {
                            if model.isCurrent(context) {
                                model.recordOperationError(FileTreeOperationError.underlying("Untrusted folder move."))
                            }
                            continue
                        }
                        let result = try await model.move(source, intoDirectory: destination, context: context)
                        didMove(source, result.url)
                    } catch {
                        if model.isCurrent(context) {
                            model.recordOperationError(error)
                        }
                    }
                }
            }
            return true
        })
        .dropDestination(for: URL.self, action: { urls, _ in
            guard !row.entry.isPackage else { return false }
            let destination = destinationDirectory
            let context = model.beginOperation()
            Task {
                for source in urls where source.standardizedFileURL != destination {
                    do {
                        _ = try await model.copyExternal(source, intoDirectory: destination, context: context)
                    } catch {
                        if model.isCurrent(context) {
                            model.recordOperationError(error)
                        }
                    }
                }
            }
            return !urls.isEmpty
        })
        .contextMenu {
            Button("New File") { create(in: destinationDirectory, isDirectory: false) }
                .accessibilityIdentifier("newFileButton")
            Button("New Folder") { create(in: destinationDirectory, isDirectory: true) }
                .accessibilityIdentifier("newFolderButton")
            Divider()
            Button("Rename") { model.renamingURL = row.entry.url }
            Button("Duplicate") {
                let context = model.beginOperation()
                Task {
                    do {
                        _ = try await model.duplicate(row.entry.url, context: context)
                    } catch {
                        if model.isCurrent(context) {
                            model.recordOperationError(error)
                        }
                    }
                }
            }
            Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([row.entry.url]) }
            Divider()
            Button("Move to Trash", role: .destructive, action: requestMoveToTrash)
        }
    }

    private var destinationDirectory: URL {
        (row.entry.isDirectory && !row.entry.isPackage) ? row.entry.url : row.entry.url.deletingLastPathComponent()
    }

    private func commitRename() {
        let old = row.entry.url
        guard model.renamingURL == old else { return }
        let context = model.beginOperation()
        Task {
            do {
                let result = try await model.rename(old, to: newName, context: context)
                didRename(old, result.url)
                if result.isCurrent {
                    model.renamingURL = nil
                }
            } catch {
                if model.isCurrent(context) {
                    model.recordOperationError(error)
                    model.renamingURL = nil
                }
            }
        }
    }

    private func create(in directory: URL, isDirectory: Bool) {
        let context = model.beginOperation()
        Task {
            do {
                let result = try await (isDirectory
                    ? model.createFolder(in: directory, context: context)
                    : model.createFile(in: directory, context: context))
                if result.isCurrent {
                    didCreate(result.url, isDirectory, context)
                }
            } catch {
                if model.isCurrent(context) {
                    model.recordOperationError(error)
                }
            }
        }
    }

    private func requestMoveToTrash() {
        let alert = NSAlert()
        alert.messageText = "Move \"\(row.entry.name)\" to Trash?"
        alert.informativeText = "You can recover it from the Trash in Finder."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        guard let window = NSApp.keyWindow else { return }
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            Task { @MainActor in
                let context = model.beginOperation()
                do {
                    let result = try await model.moveToTrash(row.entry.url, context: context)
                    didDelete(result.url)
                } catch {
                    if model.isCurrent(context) {
                        model.recordOperationError(error)
                    }
                }
            }
        }
    }
}

struct FileTreeInternalDrag: Codable, Transferable {
    let url: URL
    private let token: UUID

    @MainActor
    static func issue(url: URL, from model: FileTreeModel) -> Self {
        FileTreeDragRegistry.shared.removeExpiredEntries()
        let token = UUID()
        FileTreeDragRegistry.shared.entries[token] = .init(
            modelID: ObjectIdentifier(model), root: model.root, source: url.standardizedFileURL, issuedAt: .now
        )
        return Self(url: url.standardizedFileURL, token: token)
    }

    @MainActor
    static func trustedURL(from item: Self, for model: FileTreeModel) -> URL? {
        FileTreeDragRegistry.shared.removeExpiredEntries()
        guard let entry = FileTreeDragRegistry.shared.entries.removeValue(forKey: item.token),
              entry.modelID == ObjectIdentifier(model), entry.root == model.root,
              entry.source == item.url.standardizedFileURL,
              model.containsCurrentNode(entry.source) else { return nil }
        return entry.source
    }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .macDownFileTreeItem)
    }
}

@MainActor
private final class FileTreeDragRegistry {
    struct Entry {
        let modelID: ObjectIdentifier
        let root: URL?
        let source: URL
        let issuedAt: Date
    }

    static let shared = FileTreeDragRegistry()
    var entries: [UUID: Entry] = [:]

    func removeExpiredEntries(now: Date = .now) {
        entries = entries.filter { now.timeIntervalSince($0.value.issuedAt) < 30 }
    }
}

extension UTType {
    static let macDownFileTreeItem = UTType(exportedAs: "com.joncallim.macdown2.file-tree-item")
}
