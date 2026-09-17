import Foundation

/// Generic failures from `DiagramWebKitPool`/`DiagramHarnessPage`
/// (epic-21-implementation.md §3.1). A caller's own renderer (e.g.
/// `D2WebRenderer`) maps these to its own domain error type
/// (`D2RenderError`), matching how `MermaidWebRenderer` owns
/// `MermaidRenderError` itself rather than exposing a shared error type
/// across languages — only the pool/page mechanics are shared, not error
/// semantics, which genuinely differ per language (a language-specific
/// invalid-syntax message has no shared shape to generalize).
public enum DiagramPoolError: Error, Sendable, Equatable {
    case timedOut
    /// The harness resource could not be found/loaded, or produced a
    /// result of an unexpected shape.
    case pageUnavailable
}
