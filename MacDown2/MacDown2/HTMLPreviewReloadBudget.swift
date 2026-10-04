/// Bounds how often a terminated WebContent process is reloaded. A page that reliably kills the process (a huge
/// inline SVG, a memory-pressure kill) would otherwise crash and reload at full speed until the pane is closed;
/// one reload is allowed per successful load, after which the pane stays as it is until the next real update.
struct HTMLPreviewReloadBudget {
    static let reloadsPerSuccessfulLoad = 1
    private var remaining = Self.reloadsPerSuccessfulLoad

    mutating func consumeReload() -> Bool {
        guard remaining > 0 else { return false }
        remaining -= 1
        return true
    }

    mutating func loadSucceeded() {
        remaining = Self.reloadsPerSuccessfulLoad
    }
}
