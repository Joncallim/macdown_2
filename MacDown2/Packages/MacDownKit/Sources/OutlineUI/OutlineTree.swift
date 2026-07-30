import MarkdownEngine

public enum OutlineTree {
    /// Stack fold over document-ordered headings (D3). O(n): each heading is
    /// pushed once and attached to its parent once.
    ///
    /// - Skipped levels attach to the nearest shallower ancestor; no
    ///   placeholder node is invented for the skipped level.
    /// - A heading shallower than everything before it starts a new root.
    /// - `level` is preserved from the source heading for display; nesting
    ///   comes from tree position, never from `level`.
    /// - Empty input → empty output.
    public static func build(from headings: [HeadingItem]) -> [OutlineItem] {
        guard !headings.isEmpty else { return [] }

        var roots: [OutlineItem] = []
        var stack: [Frame] = []

        func closeFrames(shallowerThan level: Int) {
            while let top = stack.last, top.heading.level >= level {
                stack.removeLast()
                let item = OutlineItem(
                    id: top.ordinal,
                    level: top.heading.level,
                    title: top.heading.title,
                    lineRange: top.heading.lineRange,
                    children: top.children
                )
                if !stack.isEmpty {
                    stack[stack.count - 1].children.append(item)
                } else {
                    roots.append(item)
                }
            }
        }

        for (ordinal, heading) in headings.enumerated() {
            closeFrames(shallowerThan: heading.level)
            stack.append(Frame(heading: heading, ordinal: ordinal))
        }
        closeFrames(shallowerThan: Int.min)

        return roots
    }

    /// Depth-first document order, honouring `collapsed`: a collapsed item is
    /// present, its descendants are not. This is exactly the sequence arrow
    /// keys traverse and the order `List` renders (D6).
    ///
    /// Each row carries its tree depth so the view can indent by position
    /// rather than by `level` (D3). Depth belongs here, not in the view: it is
    /// a property of the tree, and keeping it here means the traversal the
    /// sidebar actually renders is the one these tests cover.
    public static func visibleRows(_ items: [OutlineItem], collapsed: Set<Int>) -> [OutlineRow] {
        var result: [OutlineRow] = []
        appendVisible(items, collapsed: collapsed, depth: 0, into: &result)
        return result
    }

    /// Every id in the tree, depth-first. The *last* step of reconciling
    /// `collapsed` and the navigation cursor against a re-parse — it drops
    /// ids the new tree does not contain at all. It is **not** sufficient on
    /// its own; run `OutlineIdentityMap.remap` first (D4).
    public static func allIDs(_ items: [OutlineItem]) -> Set<Int> {
        var result: Set<Int> = []
        insertIDs(items, into: &result)
        return result
    }

    /// Finds the item with `id` anywhere in the tree.
    public static func item(withID id: Int, in items: [OutlineItem]) -> OutlineItem? {
        for item in items {
            if item.id == id {
                return item
            }
            if let found = self.item(withID: id, in: item.children) {
                return found
            }
        }
        return nil
    }

    private struct Frame {
        let heading: HeadingItem
        let ordinal: Int
        var children: [OutlineItem] = []
    }

    private static func appendVisible(
        _ items: [OutlineItem],
        collapsed: Set<Int>,
        depth: Int,
        into result: inout [OutlineRow]
    ) {
        for item in items {
            result.append(OutlineRow(item: item, depth: depth))
            if !collapsed.contains(item.id) {
                appendVisible(item.children, collapsed: collapsed, depth: depth + 1, into: &result)
            }
        }
    }

    private static func insertIDs(_ items: [OutlineItem], into result: inout Set<Int>) {
        for item in items {
            result.insert(item.id)
            insertIDs(item.children, into: &result)
        }
    }
}
