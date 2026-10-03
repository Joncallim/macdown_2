import AppKit

extension WindowCoordinator {
    /// Only a DOCUMENT window can host a new tab. `NSApp.keyWindow` can be Settings, About,
    /// the welcome window or a palette panel (Cmd-T, a Finder open or "Edit Snippets…" while
    /// one is key): AppKit accepts `addTabbedWindow` on any of them, so the document landed
    /// as a tab inside that window.
    static func tabHost(_ candidate: NSWindow?) -> NSWindow? {
        guard let candidate, candidate.delegate is WindowController else { return nil }
        return candidate
    }
}
