/// Bounds how often a terminated WebContent process is reloaded. A page that reliably kills the process (a huge
/// inline SVG, a memory-pressure kill) would otherwise crash and reload at full speed until the pane is closed;
/// one reload is allowed per document, after which the pane stays as it is until the next real update. The budget is
/// restored only when a new document is loaded — NOT on `didFinish`, which a page that dies after its first paint
/// (a late huge SVG) would reach on every reload, resetting the budget and looping forever.
struct HTMLPreviewReloadBudget {
    static let reloadsPerDocument = 1
    private var remaining = Self.reloadsPerDocument

    mutating func consumeReload() -> Bool {
        guard remaining > 0 else { return false }
        remaining -= 1
        return true
    }

    mutating func documentChanged() {
        remaining = Self.reloadsPerDocument
    }
}
