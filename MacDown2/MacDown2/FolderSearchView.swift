import SwiftUI
import TextSearch

/// Folder search's sidebar content (EPIC-22 §6.16, Slice 7b): a search
/// field plus results grouped by file, streamed in as `FolderSearchModel`
/// finds them. Embedded directly in `SidebarView`'s own `List` (inside the
/// `.search` section's `DisclosureGroup`, like `.folder`/`.outline`), not a
/// floating panel — see `SidebarSection.search`'s own doc comment for why.
///
/// Each result row shows the matched file and its match count; activating
/// a row opens that file and reveals its first match
/// (`WindowCoordinator.openFolderSearchResult`), the same "open via the
/// existing document-open path" precedent Quick Open already established
/// (§6.15). Per-match line/column and a contextual excerpt (issue #112's
/// own "file, line, column and contextual excerpt") are deferred to a
/// follow-up polish pass — `SearchMatch` itself only carries a UTF-16
/// range today, and computing an excerpt per match would mean re-reading
/// file content the engine has already discarded once matching finished;
/// this is a real, disclosed gap, not something to silently skip.
struct FolderSearchView: View {
    @Bindable var model: FolderSearchModel
    let onOpen: (FolderSearchMatch) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("Search in Folder…", text: $model.query)
                .textFieldStyle(.plain)
                .padding(.vertical, 4)
                .accessibilityLabel("Folder search")
                .accessibilityIdentifier("folderSearchField")

            statusLine
        }
        .padding(.horizontal, 4)

        ForEach(model.results, id: \.relativePath) { fileMatch in
            Button {
                onOpen(fileMatch)
            } label: {
                FolderSearchResultRow(fileMatch: fileMatch)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("folderSearchResult-\(fileMatch.relativePath)")
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch (model.query.isEmpty, model.isSearching, model.outcome) {
        case (true, _, _):
            EmptyView()
        case (false, true, _):
            Text("Searching…")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("folderSearchStatus")
        case (false, false, .truncated):
            Text("Results truncated — refine your search")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("folderSearchStatus")
        case (false, false, _) where model.results.isEmpty:
            Text("No Results")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("folderSearchStatus")
        case (false, false, _):
            EmptyView()
        }
    }
}

private struct FolderSearchResultRow: View {
    let fileMatch: FolderSearchMatch

    var body: some View {
        HStack {
            // A file's own relative path, not user-facing UI text — never
            // translated, matching `QuickOpenRowView`'s own `Text(verbatim:)`
            // use for the same reason.
            Text(verbatim: fileMatch.relativePath)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer()
            Text(verbatim: "\(fileMatch.matches.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(fileMatch.relativePath), \(fileMatch.matches.count) matches")
    }
}
