/// Cross-checks the menu catalog, the literal titles found in the `Commands`
/// sources, and `AppPaletteCommand.standard` (issue #117 item 4). Mirrors
/// `FormatRegistryConsistency`: a pure `validate(...) -> Report` so a test can
/// also feed it deliberately drifted inputs and prove it complains.
enum CommandRegistryConsistency {
    struct Report: Equatable {
        var issues: [String] = []
        var isConsistent: Bool {
            issues.isEmpty
        }
    }

    static func validate(
        catalog: [CommandDescriptor],
        paletteEntries: [(id: String, title: String)],
        sourceMenuTitles: Set<String>
    ) -> Report {
        var report = Report()
        var catalogTitles: Set<String> = []
        var claimedPaletteIDs: [String: String] = [:]
        for descriptor in catalog {
            if !catalogTitles.insert(descriptor.menuTitle).inserted {
                report.issues.append("catalog lists '\(descriptor.menuTitle)' more than once")
            }
            if !sourceMenuTitles.contains(descriptor.menuTitle) {
                report.issues
                    .append("catalog entry '\(descriptor.menuTitle)' matches no menu item in the Commands sources")
            }
            if case let .palette(id) = descriptor.disposition,
               let other = claimedPaletteIDs.updateValue(descriptor.menuTitle, forKey: id) {
                report.issues.append("palette id '\(id)' claimed by both '\(other)' and '\(descriptor.menuTitle)'")
            }
        }
        for title in sourceMenuTitles.subtracting(catalogTitles).sorted() {
            report.issues.append("menu item '\(title)' has no catalog entry")
        }
        report.issues += paletteIssues(paletteEntries, claimedPaletteIDs: claimedPaletteIDs)
        return report
    }

    private static func paletteIssues(
        _ entries: [(id: String, title: String)],
        claimedPaletteIDs: [String: String]
    ) -> [String] {
        var issues: [String] = []
        var paletteIDs: Set<String> = []
        for entry in entries {
            if !paletteIDs.insert(entry.id).inserted {
                issues.append("palette lists id '\(entry.id)' more than once")
            }
            guard let menuTitle = claimedPaletteIDs[entry.id] else {
                issues.append("palette entry '\(entry.id)' has no catalog record")
                continue
            }
            if menuTitle != entry.title {
                issues
                    .append(
                        "palette entry '\(entry.id)' is titled '\(entry.title)' but its menu item is '\(menuTitle)'"
                    )
            }
        }
        for (id, menuTitle) in claimedPaletteIDs.sorted(by: { $0.key < $1.key }) where !paletteIDs.contains(id) {
            issues.append("catalog marks '\(menuTitle)' palette-eligible as '\(id)' but the palette has no such entry")
        }
        return issues
    }
}
