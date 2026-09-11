/// E14B: split out of `WindowCoordinator.swift`'s main class body to stay
/// under the `type_body_length` lint budget, matching
/// `WindowCoordinator+SessionRestore.swift`'s same reason.
extension WindowCoordinator {
    /// Stateless text-filter-command orchestrator for the active document, a
    /// computed property mirroring `exportCoordinator`'s same shape.
    var textFilterCoordinator: TextFilterCoordinator {
        TextFilterCoordinator(coordinator: self)
    }
}
