import Foundation

// Diagnostic branch only: this probes new private fixtures, not application
// behavior. A successful workflow is never complete integration-test evidence.
let manager = FileManager.default
let run = UUID().uuidString
let roots = [manager.temporaryDirectory, manager.homeDirectoryForCurrentUser]
var results: [[String: Any]] = []
for (index, parent) in roots.enumerated() {
    let root = parent.appendingPathComponent("mostlytext-bookmark-probe-" + run)
    try manager.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? manager.removeItem(at: root) }
    let file = root.appendingPathComponent("fixture.md")
    try Data("private diagnostic fixture".utf8).write(to: file)
    let alias = root.appendingPathComponent("alias")
    try manager.createSymbolicLink(at: alias, withDestinationURL: file)
    for (kind, lexical) in [("file", file), ("folder", root), ("alias", alias)] {
        let physical = lexical.standardizedFileURL.resolvingSymlinksInPath().standardizedFileURL
        for scoped in [true, false] {
            var item: [String: Any] = ["mode": CommandLine.arguments.last ?? "unknown", "root": index == 0 ? "temporary" : "home", "kind": kind, "scoped": scoped, "lexical": lexical.path, "physical": physical.path]
            do {
                let data = try physical.bookmarkData(options: scoped ? .withSecurityScope : [])
                var stale = false
                let resolved = try URL(resolvingBookmarkData: data, options: scoped ? .withSecurityScope : [], relativeTo: nil, bookmarkDataIsStale: &stale)
                item["resolved"] = resolved.path
                item["stale"] = stale
                item["success"] = true
            } catch {
                let failure = error as NSError
                item["success"] = false
                item["errorDomain"] = failure.domain
                item["errorCode"] = failure.code
                item["error"] = failure.description
            }
            results.append(item)
        }
    }
}
let data = try JSONSerialization.data(withJSONObject: results, options: [.sortedKeys, .prettyPrinted])
print(String(decoding: data, as: UTF8.self))
