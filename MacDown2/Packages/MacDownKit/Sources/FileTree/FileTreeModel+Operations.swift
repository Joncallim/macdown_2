import Foundation

@MainActor
public extension FileTreeModel {
    func createFile(
        in directory: URL,
        context: FileTreeOperationContext? = nil
    ) async throws(FileTreeOperationError) -> FileTreeOperationResult {
        try await create(in: directory, isDirectory: false, context: context ?? beginOperation())
    }

    func createFolder(
        in directory: URL,
        context: FileTreeOperationContext? = nil
    ) async throws(FileTreeOperationError) -> FileTreeOperationResult {
        try await create(in: directory, isDirectory: true, context: context ?? beginOperation())
    }

    func rename(
        _ url: URL,
        to newName: String,
        context: FileTreeOperationContext? = nil
    ) async throws(FileTreeOperationError) -> FileTreeOperationResult {
        let context = context ?? beginOperation()
        let source = url.standardizedFileURL
        try validate(context, members: [source, source.deletingLastPathComponent()])
        guard let sourceKind = try await itemKind(at: source) else { throw .sourceMissing }
        let parent = source.deletingLastPathComponent()
        let entries = try await contents(parent)
        if let error = FileTreeNaming.validate(
            newName,
            existing: Set(entries.map(\.name)),
            currentName: source.lastPathComponent
        ) {
            throw error
        }
        let destination = parent.appendingPathComponent(newName, isDirectory: sourceKind == .directory)
        try validate(context, members: [source, destination])
        do { try await mutator.move(from: source, to: destination) } catch {
            throw operationError(error)
        }
        guard operationIsCurrent(context) else { return operationResult(destination, context: context) }
        itemWasRenamed(from: source, to: destination)
        await reload(parent, isRoot: parent == root, expectedGeneration: generation)
        return operationResult(destination, context: context)
    }

    func duplicate(
        _ url: URL,
        context: FileTreeOperationContext? = nil
    ) async throws(FileTreeOperationError) -> FileTreeOperationResult {
        let context = context ?? beginOperation()
        let source = url.standardizedFileURL
        try validate(context, members: [source, source.deletingLastPathComponent()])
        guard let sourceKind = try await itemKind(at: source) else { throw .sourceMissing }
        let parent = source.deletingLastPathComponent()
        let entries = try await contents(parent)
        let name = FileTreeNaming.duplicateName(of: source.lastPathComponent, existing: Set(entries.map(\.name)))
        let destination = parent.appendingPathComponent(name, isDirectory: sourceKind == .directory)
        try validate(context, members: [source, destination])
        do { try await mutator.copy(from: source, to: destination) } catch {
            throw operationError(error)
        }
        guard operationIsCurrent(context) else { return operationResult(destination, context: context) }
        await reload(parent, isRoot: parent == root, expectedGeneration: generation)
        return operationResult(destination, context: context)
    }

    func copyExternal(
        _ url: URL,
        intoDirectory destination: URL,
        context: FileTreeOperationContext? = nil
    ) async throws(FileTreeOperationError) -> FileTreeOperationResult {
        let context = context ?? beginOperation()
        let source = url.standardizedFileURL
        let destinationDirectory = destination.standardizedFileURL
        try validate(context, members: [destinationDirectory])
        guard let sourceKind = try await itemKind(at: source) else { throw .sourceMissing }
        guard try await itemKind(at: destinationDirectory) == .directory else { throw .destinationNotDirectory }
        if sourceKind == .directory {
            do {
                if let error = try FileTreeCopySafety.validateDirectoryCopy(
                    source: source,
                    intoDirectory: destinationDirectory
                ) {
                    throw error
                }
            } catch let error as FileTreeOperationError {
                throw error
            } catch {
                throw .underlying(error.localizedDescription)
            }
        }
        let entries = try await contents(destinationDirectory)
        if let error = FileTreeNaming.validate(
            source.lastPathComponent,
            existing: Set(entries.map(\.name)),
            currentName: nil
        ) {
            throw error
        }
        let copied = destinationDirectory.appendingPathComponent(
            source.lastPathComponent,
            isDirectory: sourceKind == .directory
        )
        try validate(context, members: [destinationDirectory, copied])
        do { try await mutator.copy(from: source, to: copied) } catch { throw operationError(error) }
        guard operationIsCurrent(context) else { return operationResult(copied, context: context) }
        await reload(destinationDirectory, isRoot: destinationDirectory == root, expectedGeneration: generation)
        return operationResult(copied, context: context)
    }

    func move(
        _ url: URL,
        intoDirectory destination: URL,
        context: FileTreeOperationContext? = nil
    ) async throws(FileTreeOperationError) -> FileTreeOperationResult {
        let context = context ?? beginOperation()
        let source = url.standardizedFileURL; let destinationDirectory = destination.standardizedFileURL
        try validate(context, members: [source, destinationDirectory])
        guard let sourceKind = try await itemKind(at: source) else { throw .sourceMissing }
        guard try await itemKind(at: destinationDirectory) == .directory else { throw .destinationNotDirectory }
        if source.deletingLastPathComponent() == destinationDirectory {
            return operationResult(source, context: context)
        }
        if sourceKind == .directory {
            do {
                if let error = try FileTreeCopySafety.validateDirectoryCopy(
                    source: source,
                    intoDirectory: destinationDirectory
                ) {
                    throw error
                }
            } catch let error as FileTreeOperationError {
                throw error
            } catch {
                throw .underlying(error.localizedDescription)
            }
        }
        let entries = try await contents(destinationDirectory)
        if let error = FileTreeNaming.validate(
            source.lastPathComponent,
            existing: Set(entries.map(\.name)),
            currentName: nil
        ) {
            throw error
        }
        let moved = destinationDirectory.appendingPathComponent(
            source.lastPathComponent,
            isDirectory: sourceKind == .directory
        )
        try validate(context, members: [source, destinationDirectory, moved])
        do { try await mutator.move(from: source, to: moved) } catch { throw operationError(error) }
        guard operationIsCurrent(context) else { return operationResult(moved, context: context) }
        itemWasRenamed(from: source, to: moved)
        await reload(
            source.deletingLastPathComponent(),
            isRoot: source.deletingLastPathComponent() == root,
            expectedGeneration: generation
        )
        await reload(destinationDirectory, isRoot: destinationDirectory == root, expectedGeneration: generation)
        return operationResult(moved, context: context)
    }

    func moveToTrash(
        _ url: URL,
        context: FileTreeOperationContext? = nil
    ) async throws(FileTreeOperationError) -> FileTreeOperationResult {
        let context = context ?? beginOperation()
        let source = url.standardizedFileURL
        try validate(context, members: [source])
        guard try await itemKind(at: source) != nil else { throw .sourceMissing }
        try validate(context, members: [source])
        do { try await mutator.trash(at: source) } catch { throw operationError(error) }
        guard operationIsCurrent(context) else { return operationResult(source, context: context) }
        evictSubtree(source)
        await reload(
            source.deletingLastPathComponent(),
            isRoot: source.deletingLastPathComponent() == root,
            expectedGeneration: generation
        )
        return operationResult(source, context: context)
    }

    func itemWasRenamed(from old: URL, to new: URL) {
        let oldKey = old.standardizedFileURL; let newKey = new.standardizedFileURL
        let previousRoot = root
        func rekey(_ key: URL) -> URL? {
            let path = key.pathComponents; let prefix = oldKey.pathComponents
            guard path.starts(with: prefix) else { return nil }
            let suffix = path.dropFirst(prefix.count).joined(separator: "/")
            return newKey.appendingPathComponent(suffix, isDirectory: key.hasDirectoryPath).standardizedFileURL
        }
        for key in rescanTasks.keys.filter({ $0.pathComponents.starts(with: oldKey.pathComponents) }) {
            rescanTasks.removeValue(forKey: key)?.cancel()
        }
        for key in reloadTokens.keys.filter({ $0.pathComponents.starts(with: oldKey.pathComponents) }) {
            reloadTokens.removeValue(forKey: key)
        }
        for key in watchers.keys.filter({ $0.pathComponents.starts(with: oldKey.pathComponents) }) {
            cancelWatcher(at: key)
        }
        expanded = Set(expanded.map { rekey($0) ?? $0 })
        var newChildren: [URL: DirectoryLoadState] = [:]
        for (key, state) in children {
            newChildren[rekey(key) ?? key] = self.rekey(state, from: oldKey, to: newKey)
        }; children = newChildren
        root = root.flatMap { rekey($0) ?? $0 }
        if root != previousRoot, let root {
            rootAccessScope = FolderAccessScope(url: root)
        }
        selectedURL = selectedURL.flatMap { rekey($0) ?? $0 }
        renamingURL = renamingURL.flatMap { rekey($0) ?? $0 }
        pendingOpenURL = pendingOpenURL.flatMap { rekey($0) ?? $0 }
        rebuildRows()
        let expectedGeneration = generation
        for url in expanded where url == root || findEntry(url)?.isDirectory == true {
            startWatching(url, expectedGeneration: expectedGeneration)
        }
    }

    private func create(
        in directory: URL,
        isDirectory: Bool,
        context: FileTreeOperationContext
    ) async throws(FileTreeOperationError) -> FileTreeOperationResult {
        let targetDirectory = directory.standardizedFileURL
        try validate(context, members: [targetDirectory])
        guard try await itemKind(at: targetDirectory) == .directory else { throw .destinationNotDirectory }
        let entries = try await contents(targetDirectory)
        var existing = Set(entries.map(\.name))
        var url: URL
        while true {
            let name = FileTreeNaming.uniqueName(
                base: "untitled",
                extension: isDirectory ? "" : "md",
                existing: existing
            )
            url = targetDirectory.appendingPathComponent(name, isDirectory: isDirectory)
            do {
                try validate(context, members: [targetDirectory, url])
                if isDirectory {
                    try await mutator.createDirectory(at: url)
                } else {
                    try await mutator.createFile(at: url)
                }
                break
            } catch let error as POSIXError where error.code == .EEXIST {
                existing.insert(name)
            } catch let error as CocoaError where error.code == .fileWriteFileExists {
                existing.insert(name)
            } catch {
                throw operationError(error)
            }
        }
        guard operationIsCurrent(context) else { return operationResult(url, context: context) }
        await reload(targetDirectory, isRoot: targetDirectory == root, expectedGeneration: generation)
        return operationResult(url, context: context)
    }

    func contents(_ url: URL) async throws(FileTreeOperationError) -> [DirectoryEntry] {
        do {
            return try await Task.detached { try self.reader.contents(of: url) }.value
        } catch {
            throw operationError(error)
        }
    }

    private func itemKind(at url: URL) async throws(FileTreeOperationError) -> FileSystemItemKind? {
        do {
            return try await mutator.itemKind(at: url)
        } catch {
            throw operationError(error)
        }
    }

    func operationIsCurrent(_ context: FileTreeOperationContext) -> Bool {
        generation == context.generation && root == context.root
    }

    private func operationResult(_ url: URL, context: FileTreeOperationContext) -> FileTreeOperationResult {
        FileTreeOperationResult(url: url.standardizedFileURL, isCurrent: operationIsCurrent(context))
    }

    private func operationError(_ error: Error) -> FileTreeOperationError {
        if let error = error as? POSIXError {
            return .posix(error.code.rawValue)
        }
        return .underlying(error.localizedDescription)
    }

    private func validate(
        _ context: FileTreeOperationContext,
        members: [URL]
    ) throws(FileTreeOperationError) {
        guard operationIsCurrent(context) else { throw .staleOperation }
        guard let root = context.root else { throw .outsideCurrentRoot }
        let rootComponents = root.standardizedFileURL.pathComponents
        guard members.allSatisfy({ $0.standardizedFileURL.pathComponents.starts(with: rootComponents) }) else {
            throw .outsideCurrentRoot
        }
    }
}
