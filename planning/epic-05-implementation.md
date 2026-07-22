# EPIC-05 Implementation Plan — Tree-sitter highlighting engine + theme system

> **Issue:** #6 — [EPIC-05] Tree-sitter highlighting engine + theme system
> **High-level spec:** `planning/epics/EPIC-05-tree-sitter-highlighting.md` (scope/acceptance are binding).
> **Branch:** `epic/05-tree-sitter-highlighting` → PR into `master`.
> **Depends on:** E01 (`FileCore.FileFormat.highlightLanguageID`), E04 (`EditorCore.EditorTextSystem` — its `textView`/`contentStorage`/`layoutManager` are the attach seam).
> **Intended pipeline:** implemented by **Kimi K2.7**, reviewed by **DeepSeek**. This document is written so that **neither has to guess intent or fill gaps.** Read **§2 (native-first stance)**, **§3 (decisions)**, and **§4.2–§4.3 (API contracts)** before writing code — reviews reject on §3 and §4.
>
> **New third-party dependencies (all MIT, pinned):** `SwiftTreeSitter` + `SwiftTreeSitterLayer` (tree-sitter/swift-tree-sitter), `Neon` + `TreeSitterClient` (ChimeHQ/Neon), and one SPM package per grammar. These are the *only* new deps and they are wrapped behind an internal protocol (§4.3) per `AGENTS.md`.

---

## 1. Ground rules (binding, carried from E00–E04)

1. **macOS 26.0 only. No availability checks.** Swift 6.2, `SWIFT_STRICT_CONCURRENCY: complete`, zero warnings.
2. **Package holds the logic; the app holds glue.** New logic lives in the SPM `Themes` and `Highlighting` modules. The app target only *wires* (creates controllers per window, injects the theme controller, adds a View menu).
3. **`Themes` is UI-model-only** (may import AppKit **only** for the `NSColor` bridging computed property; no windows, no menus). **`Highlighting` may import AppKit** (it drives an `NSTextView`), exactly like `EditorCore`.
4. **Do not churn the E04 seam.** Attach from *outside* using the public `EditorTextSystem.textView` / `.contentStorage` / `.layoutManager`. The one permitted EditorCore change is additive and optional (§4.9.1); if you can avoid it, do.
5. **Tests: Swift Testing (`@Test`)** for all logic + parse-layer performance; **temp-dir stores only**, never the real `UserDefaults`/theme-preference suite. XCTest/XCUITest only where Swift Testing has no equivalent (the visual pipeline, §7.4).
6. **CI reality (do not fight it):** `xcodebuild test` **cannot run** on the `macos-15` runner against a macOS 26 target (E03 §2.8, E04 §1). `swift test` **does** run there. **Therefore every acceptance gate that must run in CI is a `swift test` on the SwiftTreeSitter parse layer (headless — no `NSTextView`).** The Neon+NSTextView visual path is an XCUITest that is `build-for-testing` only in CI and run locally on macOS 26.
7. **Graceful degradation is a hard requirement, not a nicety.** An unknown language, a grammar that fails to load, or a query that fails to compile must degrade to *plain text with theme chrome* — never an error state, never a crash, never a blocked app build.
8. **No preview-side highlighting** (E07 owns preview code fences). No editing assists (E10). Only the **editor** is themed/highlighted here.

---

## 2. Native-first stance & Swift/SwiftUI best practices (required reading)

Per the request to prefer native APIs where they exist, this epic is built on Apple-native primitives and adds third-party code *only* where Apple ships no equivalent. Use the native option in every row below; the third-party column is used **only** for incremental parsing, for which there is no system API.

| Concern | **Native API to use** | Third-party (only where native is absent) |
|---|---|---|
| Text storage & layout | **TextKit 2** — `NSTextContentStorage`, `NSTextLayoutManager`, `NSTextViewportLayoutController` (already assembled by E04). Viewport-lazy layout is native. | — |
| Applying highlight colours | Native attribute application: `NSTextLayoutManager.setRenderingAttributes(_:for:)` **or** `NSTextStorage.addAttribute(_:value:range:)` (`.foregroundColor`, `.font` for bold/italic). Neon calls these through its `TextViewSystemInterface`. | Neon owns *when/over-what-range* to apply (viewport priority math). |
| Colours & light/dark | **`NSColor`**, `NSColor(name:dynamicProvider:)` for dynamic light/dark, `NSAppearance`/`NSApp.effectiveAppearance`, SwiftUI `@Environment(\.colorScheme)`. | — |
| Observation / reactivity | **Observation framework** (`@Observable`, `@MainActor`). **Not** Combine, **not** `ObservableObject`. Matches E02–E04. | — |
| Serialization (theme files) | **`Codable`** + `JSONDecoder`, `Bundle.module` resources. | — |
| Concurrency | **Swift structured concurrency** — `actor` for the off-main parse owner, `Task`, `@MainActor` for all AppKit. `Sendable` everywhere. | Neon/`TreeSitterClient` provide a hybrid sync/async model on top of this. |
| Timing (perf tests) | **`ContinuousClock().measure { }`**, `XCTClockMetric`/`XCTMemoryMetric` for the manual Instruments cross-check. | — |
| Incremental parsing | *No native equivalent exists* — Apple ships no incremental parser and `NSSpellChecker`/`NSDataDetector` do not do grammar-aware syntax. | **SwiftTreeSitter** (C runtime wrapper) + **SwiftTreeSitterLayer** (nested languages) + **Neon** (TextKit 2 text-view interface, viewport priority, invalidation buffering). |

**Why not roll our own over raw SwiftTreeSitter?** The SwiftTreeSitter maintainer states plainly that *"priority range calculations with TextKit 2 are extremely hard to do correctly,"* and Neon exists precisely to solve that for `NSTextView`. Hand-writing viewport-priority + invalidation math is the highest-risk way to miss the `< 50 ms` and `< 8 ms main-thread` gates. We take Neon and keep it swappable behind our own protocol (§4.3, D1).

Sources: [swift-tree-sitter](https://github.com/tree-sitter/swift-tree-sitter), [Neon](https://github.com/ChimeHQ/Neon), [tree-sitter syntax-highlighting & injections](https://tree-sitter.github.io/tree-sitter/3-syntax-highlighting.html).

---

## 3. Key architectural decisions (review anchors — do not silently deviate)

### D1 — Use Neon for the TextKit 2 attach; wrap it behind `SyntaxHighlighting`
`Highlighting` defines a small protocol `SyntaxHighlighting` (§4.3) and a concrete `NeonSyntaxHighlighter` that adapts Neon's `TextViewHighlighter`. Every caller (the app) talks to the protocol. **Rationale:** satisfies AGENTS.md ("third-party deps wrapped behind internal protocols"), keeps Neon replaceable, and gives DeepSeek one seam to audit. **Rejected:** raw SwiftTreeSitter + bespoke viewport math (risk, per §2); STTextView / CodeEditSourceEditor (full editor replacements — conflicts with E04's `NSTextView`).

### D2 — The theme model lives in the existing `Themes` module, not `Highlighting`
`Preview` and `ExportService` already depend on `Themes`. Themes are needed app-wide (editor now; preview/export later), so the model, colour parsing, shipped themes, and the `ThemeController` live in `Themes`. `Highlighting` **depends on `Themes`** and only maps tree-sitter capture names → `TokenStyle`. **Rejected:** duplicating a theme type inside `Highlighting` (would force Preview/Export to re-implement it later).

### D3 — One SPM package per grammar; a runtime registry isolates failures
Each grammar is an independent SPM package dependency, resolved and compiled separately. `GrammarRegistry` (§4.3) maps `highlightLanguageID` → a lazily-built, cached `LanguageConfiguration`, and **catches every load/compile error** so a bad grammar downgrades that one language to plain text rather than crashing or failing the build. **MVP ships 3 grammars — markdown (+markdown-inline), json, html.** Adding a grammar later = add one package dep + one registry line + (if needed) one query file. **Rejected:** a single mega-grammar target (one broken grammar breaks all); xcframeworks (heavier, unnecessary for the MVP set — revisit only if an SPM grammar proves un-buildable, see §10.4).

### D4 — Legacy themes/tests are ported from the now-tracked `legacy-reference/`
The original MacDown tree was removed when the repo was re-rooted. Its editor themes (`Resources/**/*.style`, preview CSS) and colour tests (`MPColor`/`MPUtilities`) live in the user's `legacy-reference/` backup, which **this PR un-ignores** (`.gitignore`) so it synchronises into the repo. **Kimi:** locate the real files with the searches in §4.11 and port from them. Do **not** invent theme colours from memory — read the backup. If `legacy-reference/` is absent in your checkout, STOP and flag it on the PR (do not fabricate). The behavioural contract for the colour parser (§4.11) is fully specified here regardless, so the *parser* is unambiguous even before you see the backup.

### D5 — Themes follow the system appearance; switching recolours without a reparse
`ThemeController` (§4.2) holds a `light` and a `dark` theme and exposes the resolved `current` based on an appearance the **app feeds it** (from `NSApp.effectiveAppearance`). A theme change re-runs only the attribute mapping over the *visible* range via `highlighter.invalidate(.all)` — the parse tree is untouched, so recolour is instant. **Rejected:** re-parsing on theme change (violates the "recolor without reparse" acceptance bullet).

---

## 4. Architecture

### 4.1 Module boundaries & dependency graph

```
Themes  (EXPAND stub → real model; imports Foundation, AppKit[NSColor bridge only], Observation)
  ├── ThemeColor          Sendable RGBA value + CSS/hex/named parsing (MPColor port)
  ├── TokenStyle          colour + bold/italic/underline for one capture class
  ├── EditorChrome        background/foreground/caret/selection/currentLine/invisibles
  ├── ThemeAppearance     .light | .dark
  ├── Theme               Codable/Sendable/Equatable: id, name, appearance, chrome, tokenStyles
  ├── BundledThemes       loads the 2 shipped JSON themes from Bundle.module
  ├── ThemePreferenceStoring / UserDefaultsThemePreferenceStore   persisted selection (temp-dir in tests)
  └── ThemeController     @MainActor @Observable: light+dark pair, fed appearance, publishes `current`

Highlighting  (EXPAND stub → real engine; imports EditorCore, Themes, SwiftTreeSitter,
               SwiftTreeSitterLayer, Neon, TreeSitterClient, + grammar targets)
  ├── HighlightCaptureName   canonical capture set + fallback chain (dot-trim)
  ├── GrammarRegistry        @MainActor: highlightLanguageID → LanguageConfiguration? (cached, failure-isolated)
  ├── SyntaxHighlighting     PROTOCOL — the internal seam the app talks to (wraps Neon)
  ├── NeonSyntaxHighlighter  concrete: builds TextViewHighlighter.Configuration, attaches to EditorTextSystem
  └── SyntaxHighlightStore   @MainActor cache: identity (WorkspaceTab.id) → SyntaxHighlighting (parallels EditorTextSystemStore)

Depends on:  EditorCore (E04), Themes, FileCore (via EditorCore/format ids)
Consumed by: App target — WindowController owns a SyntaxHighlightStore per window (parallel to editorStore)
```

Dependency direction is strictly `Highlighting → {EditorCore, Themes}`. Neither `EditorCore` nor `Themes` imports `Highlighting`. This is why the highlighter attaches from the outside (D1) and cannot be a stored property of `EditorTextSystem`.

### 4.2 Public API contract — `Themes` module

```swift
import Foundation
import AppKit          // NSColor bridging ONLY
import Observation

/// A colour as sRGB components in 0...1. Pure value type; no AppKit in the stored form.
public struct ThemeColor: Codable, Sendable, Equatable {
    public var red: Double, green: Double, blue: Double, alpha: Double
    public init(red: Double, green: Double, blue: Double, alpha: Double = 1)

    /// Parse a CSS/hex/named colour string. Returns nil on any malformed input.
    /// Grammar and cases are specified in §4.11 (the MPColor port). Case-insensitive.
    public init?(cssString: String)

    /// Bridge to AppKit at the edge. Always sRGB. Computed, not stored (keeps `Codable`).
    public var nsColor: NSColor { get }
}

/// Style for one capture class. `bold`/`italic` synthesise a font trait at apply time.
public struct TokenStyle: Codable, Sendable, Equatable {
    public var color: ThemeColor
    public var bold: Bool
    public var italic: Bool
    public var underline: Bool
    public init(color: ThemeColor, bold: Bool = false, italic: Bool = false, underline: Bool = false)
}

/// Non-token editor colours (applied to the NSTextView itself, not per-run).
public struct EditorChrome: Codable, Sendable, Equatable {
    public var background: ThemeColor
    public var foreground: ThemeColor          // default text colour (also used for plain text)
    public var caret: ThemeColor               // insertionPointColor
    public var selection: ThemeColor           // selectedTextAttributes background
    public var currentLine: ThemeColor?        // optional; reserved for E10 current-line highlight
    public var invisibles: ThemeColor?         // reserved (EditorConfiguration.showsInvisibles)
}

public enum ThemeAppearance: String, Codable, Sendable, Equatable { case light, dark }

/// A complete theme. `tokenStyles` is keyed by CANONICAL capture name (§4.4).
/// Lookup MUST go through `style(for:)`, which applies the fallback chain — do not
/// index `tokenStyles` directly.
public struct Theme: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var appearance: ThemeAppearance
    public var chrome: EditorChrome
    public var tokenStyles: [String: TokenStyle]

    /// Resolve a capture name to a style using the §4.4 fallback chain
    /// ("keyword.control" → "keyword.control" → "keyword" → nil). nil → use chrome.foreground.
    public func style(for captureName: String) -> TokenStyle?
}

/// Loads the two shipped JSON themes from Bundle.module (Sources/Themes/Themes/*.json).
public enum BundledThemes {
    public static let light: Theme      // ported light theme (§4.11 / D4)
    public static let dark: Theme       // ported dark theme
    public static let all: [Theme]
    /// Decodes a bundled theme by resource name; traps only on a build-broken bundle.
    static func load(_ resource: String) -> Theme
}

/// Persists which light/dark theme the user picked. UserDefaults-backed in the app,
/// injectable fake / temp suite in tests (never the real suite — §1.5).
public protocol ThemePreferenceStoring: Sendable {
    func loadSelection() -> (lightID: String, darkID: String)?
    func saveSelection(lightID: String, darkID: String)
}
public struct UserDefaultsThemePreferenceStore: ThemePreferenceStoring {
    public init(suiteName: String? = nil)
    // ...
}

/// Single source of truth for the active theme. App-wide (one instance).
@MainActor @Observable
public final class ThemeController {
    public private(set) var light: Theme
    public private(set) var dark: Theme
    public private(set) var appearance: ThemeAppearance
    /// The resolved active theme = (appearance == .dark ? dark : light).
    public var current: Theme { get }

    public init(
        available: [Theme] = BundledThemes.all,
        preferenceStore: ThemePreferenceStoring = UserDefaultsThemePreferenceStore(),
        appearance: ThemeAppearance = .light
    )

    public var available: [Theme] { get }
    /// Fed by the app from NSApp.effectiveAppearance changes (Themes stays AppKit-observation-free).
    public func setAppearance(_ appearance: ThemeAppearance)
    /// Select a theme; if its appearance is light it becomes `light`, else `dark`. Persists.
    public func select(_ theme: Theme)
    public func selectLight(id: String)
    public func selectDark(id: String)
}
```

**Contract notes (binding):**
- `ThemeColor.nsColor` MUST build with `NSColor(srgbRed:green:blue:alpha:)` (explicit sRGB), never `NSColor(calibratedRed:...)`.
- `Theme` MUST NOT store `NSColor` (breaks `Codable`/`Sendable`/`Equatable`). Convert only at apply time.
- `ThemeController` is the **only** mutable theme state. The app owns exactly one and injects it into every `SyntaxHighlighting`.

### 4.3 Public API contract — `Highlighting` module

```swift
import AppKit
import EditorCore
import Themes
import SwiftTreeSitter
import SwiftTreeSitterLayer
import Neon           // TextViewHighlighter, TokenAttributeProvider
// grammar C modules imported inside GrammarRegistry only

/// Canonical highlight capture classes we theme against (§4.4). The registry/themes
/// key off these; unknown captures fall back by trimming trailing dotted components.
public enum HighlightCaptureName {
    /// Trim one trailing ".segment" for fallback: "keyword.control" -> "keyword". nil at root.
    public static func fallback(_ name: String) -> String?
    public static let canonical: Set<String>   // the documented set in §4.4
}

/// Maps a FileFormat.highlightLanguageID to a tree-sitter LanguageConfiguration.
/// Lazily builds + caches; every failure is caught and cached as `nil` (graceful degradation).
@MainActor
public final class GrammarRegistry {
    public init()
    /// nil ⇒ no grammar for this id ⇒ caller must degrade to plain text. Never throws.
    public func configuration(for highlightLanguageID: String?) -> LanguageConfiguration?
    /// The languageProvider Neon/SwiftTreeSitterLayer call to resolve injected languages
    /// (e.g. "markdown_inline", or a fenced code block's info-string language). Returns nil
    /// for unknown injected languages so that region stays plain (graceful).
    public var languageProvider: LanguageLayer.LanguageProvider { get }
    /// Ids the registry can currently satisfy (test seam).
    public var supportedLanguageIDs: Set<String> { get }
}

/// The internal seam the app talks to. One instance per open document/text system.
@MainActor
public protocol SyntaxHighlighting: AnyObject {
    /// Recolour the visible range for a new theme WITHOUT reparsing.
    func applyTheme(_ theme: Theme)
    /// Swap language (e.g. after Save As changes the format). Rebuilds the parser.
    func setLanguage(_ highlightLanguageID: String?)
    /// Force a full re-highlight (external reload / conflict resolution reset the text).
    func invalidateAll()
    /// Break references so the NSTextView graph deallocates. Call on tab close.
    func tearDown()
}

/// Concrete highlighter: wraps Neon's TextViewHighlighter over an E04 EditorTextSystem.
@MainActor
public final class NeonSyntaxHighlighter: SyntaxHighlighting {
    /// - textSystem: the E04 system whose `.textView` we attach to (its stack stays owned by EditorCore).
    /// - languageID: FileFormat.highlightLanguageID (nil / unknown ⇒ plain text + chrome only).
    /// - theme: initial theme; chrome is applied to the text view immediately.
    /// - registry: shared grammar registry (one per app is fine; @MainActor).
    public init(
        textSystem: EditorTextSystem,
        languageID: String?,
        theme: Theme,
        registry: GrammarRegistry
    )
    // SyntaxHighlighting conformance …
}

/// Caches one SyntaxHighlighting per tab identity. Parallels EditorTextSystemStore; owned per window.
@MainActor
public final class SyntaxHighlightStore {
    public init(registry: GrammarRegistry = GrammarRegistry())
    /// Returns the existing highlighter or builds one for this text system.
    public func highlighter(
        for identity: String,
        textSystem: EditorTextSystem,
        languageID: String?,
        theme: Theme
    ) -> SyntaxHighlighting
    public func evict(_ identity: String)          // calls tearDown() then drops it
    public func evictAll()
    /// Re-theme every live highlighter (called when ThemeController.current changes).
    public func applyThemeToAll(_ theme: Theme)
    public var liveIdentities: Set<String> { get }  // test seam
}
```

**How `NeonSyntaxHighlighter.init` builds Neon (reference — adapt to the pinned Neon version's exact symbols):**

```swift
// 1. Apply chrome immediately (works even with no grammar → plain text is still themed):
textSystem.textView.backgroundColor      = theme.chrome.background.nsColor
textSystem.textView.textColor            = theme.chrome.foreground.nsColor
textSystem.textView.insertionPointColor  = theme.chrome.caret.nsColor
textSystem.textView.selectedTextAttributes = [.backgroundColor: theme.chrome.selection.nsColor]

// 2. Resolve grammar. nil ⇒ store `self.highlighter = nil`; done (plain text, graceful).
guard let config = registry.configuration(for: languageID) else { return }

// 3. Build Neon config. `attributeProvider` reads `self.currentTheme` (a stored var) so
//    theme changes recolour by re-running it — NO reparse.
let attributeProvider: TokenAttributeProvider = { [weak self] token in
    guard let self else { return [:] }
    let style = self.currentTheme.style(for: token.name)   // §4.4 fallback inside
    var attrs: [NSAttributedString.Key: Any] = [
        .foregroundColor: (style?.color ?? self.currentTheme.chrome.foreground).nsColor,
    ]
    if style?.bold == true || style?.italic == true {
        attrs[.font] = self.styledFont(bold: style?.bold ?? false, italic: style?.italic ?? false)
    }
    if style?.underline == true { attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue }
    return attrs
}

let neon = try TextViewHighlighter(
    textView: textSystem.textView,
    configuration: TextViewHighlighter.Configuration(
        languageConfiguration: config,
        attributeProvider: attributeProvider,
        languageProvider: registry.languageProvider,          // injections (§4.7)
        locationTransformer: Self.locationTransformer(for: textSystem.textView)  // §4.5
    )
)
neon.observeEnclosingScrollView()     // viewport-driven highlighting
```

- `applyTheme(_:)` sets `self.currentTheme = theme`, re-applies chrome (step 1), then `neon.invalidate(.all)` (recolour, no reparse) — **or** `self.highlighter == nil` path just re-applies chrome.
- `setLanguage(_:)` tears down the current Neon instance and rebuilds (or drops to nil if unknown).
- `tearDown()` releases the Neon instance and nils delegates; a **weak-ref test** (§7.2) proves the text-view graph deallocates after `evict`.

### 4.4 Canonical capture names & fallback (the theme key space)

Themes key on this canonical set (standard tree-sitter highlight groups). Grammar queries emit dotted names; lookup trims trailing segments until a hit or root. **This table is the contract** — `BundledThemes` must define styles for every root name; grammars may emit finer names that fall back.

| Canonical root | Emitted examples that fall back to it | Typical role |
|---|---|---|
| `keyword` | `keyword.control`, `keyword.function`, `keyword.operator`, `keyword.return` | language keywords |
| `string` | `string.special`, `string.escape` | string literals |
| `comment` | `comment.line`, `comment.block`, `comment.documentation` | comments |
| `number` | `number.float`, `constant.numeric` → (see note) | numeric literals |
| `constant` | `constant.builtin`, `constant.character` | constants / builtins |
| `function` | `function.call`, `function.method`, `function.builtin` | function names |
| `type` | `type.builtin`, `type.definition` | types / classes |
| `variable` | `variable.builtin`, `variable.parameter`, `variable.member` | identifiers |
| `property` | `property`, `attribute` | object properties / attrs |
| `operator` | `operator` | operators |
| `punctuation` | `punctuation.delimiter`, `punctuation.bracket`, `punctuation.special` | punctuation |
| `tag` | `tag`, `tag.attribute` | HTML/XML tags |
| `markup.heading` | `markup.heading.1`…`.6` | Markdown headings |
| `markup.bold` / `markup.italic` / `markup.link` / `markup.raw` / `markup.list` / `markup.quote` | markdown inline & block | Markdown styling |
| `label` | `label` | labels |
| `embedded` | `none`/injected fallback | injected regions |

**Fallback algorithm (exact):** `style(for:)` tries the full name, then repeatedly drops the last `.`-delimited segment (`HighlightCaptureName.fallback`), returning the first `TokenStyle` present in `tokenStyles`; if none, returns `nil` and the caller uses `chrome.foreground`. Note: some grammars emit `constant.numeric` for numbers — `BundledThemes` should alias by defining both `number` and `constant.numeric`, **or** rely on fallback to `constant`. Pick one and document it in the theme JSON comment; do not leave numbers unstyled.

### 4.5 Threading / concurrency model

- **All AppKit and all of `Highlighting`/`ThemeController` are `@MainActor`.** `Theme`, `ThemeColor`, `TokenStyle` are `Sendable` value types and cross actors freely.
- **Parsing runs off the main thread inside Neon/`TreeSitterClient`** (its hybrid sync/async model: tiny docs may parse synchronously; large docs parse on a background executor and post results back to the main actor for attribute application). We do **not** hand-roll a parse actor for the *editor* path — Neon owns it. This is what satisfies "no main-thread parse" and "zero main-thread parse time > 8 ms."
- **The only main-thread per-keystroke work is attribute application over the changed/visible range** — bounded by viewport size, not document size.
- `locationTransformer` maps a UTF-16 offset → `Point(row:column:)`. **Exact contract:** `row` = number of `\n` before the offset; `column` = UTF-16 code-unit distance from the offset back to the previous `\n` (or string start). Parse encoding is **UTF-16** (aligns with `NSRange`/`NSString`). Pin Neon's provided NSTextView helper if the vendored version ships one; otherwise implement this literally. A wrong transformer breaks injections and multi-line captures — get it right and unit-test it (§7.1).
- For the **headless parse-layer tests** (§7.3) we *do* use SwiftTreeSitter directly (`Parser`, `.utf16` encoding, `Query`, `SwiftTreeSitterLayer.LanguageLayer`) — no `NSTextView`, no Neon — because that path runs under `swift test` in CI.

### 4.6 Incremental & viewport highlighting

- Neon computes the **visible range** from the enclosing `NSScrollView` (`observeEnclosingScrollView()`), highlights only what is visible + a margin, and re-validates as the user scrolls. On edit, `TreeSitterClient` performs an incremental reparse (`tree.edit(InputEdit)` + `parser.parse(tree: old, …)`), and `RangeInvalidationBuffer` coalesces the invalidated range so only the affected fragments restyle. This is the mechanism behind acceptance bullet 1 ("editing inside a fenced code block re-highlights only the affected range").
- We must **not** force whole-document layout or highlighting on open (mirror E04 §2.5). Never call `invalidateAll()` on open for a large doc — Neon's initial pass is viewport-scoped; let it drive.

### 4.7 Markdown injection (fenced code blocks + inline)

Markdown needs **two** grammars plus injected fence languages:
1. `tree_sitter_markdown()` — block structure (headings, lists, fenced code blocks).
2. `tree_sitter_markdown_inline()` — inline (emphasis, links, code spans), injected into inline regions.
3. The fenced code block's info string injects that language (```` ```swift ````→ swift), resolved through `GrammarRegistry.languageProvider`.

Register both markdown grammars; `languageProvider` returns configs for `markdown_inline` and for any MVP fence language present (`json`, `html`, `markdown`). **Unknown fence language ⇒ provider returns nil ⇒ that fence stays plain** (graceful; never an error).

**Queries:** prefer each grammar package's bundled `queries/highlights.scm` + `injections.scm` (loaded by `LanguageConfiguration(_:name:)` from its SPM bundle `TreeSitter{Name}_TreeSitter{Name}`). If a grammar package ships no Swift-loadable queries, **vendor** them under `Sources/Highlighting/Queries/<lang>/{highlights,injections}.scm` and load via `LanguageConfiguration(_:name:queriesURL:)`. The markdown injection fallback (vendor these verbatim if the package lacks them):

```scheme
; Queries/markdown/injections.scm
(fenced_code_block
  (info_string (language) @injection.language)
  (code_fence_content) @injection.content)

((inline) @injection.content
 (#set! injection.language "markdown_inline"))
```

### 4.8 Graceful degradation (the failure matrix)

| Situation | Behaviour (required) |
|---|---|
| `highlightLanguageID == nil` (plaintext) | No Neon instance; chrome applied; plain text in `chrome.foreground`. |
| Unknown `highlightLanguageID` | Same as above. `GrammarRegistry.configuration` returns nil (cached). |
| Grammar package present but `LanguageConfiguration` init throws / query fails to compile | Caught in `GrammarRegistry`; cached as nil; language degrades to plain text. Log once. |
| Injected fence language unknown | `languageProvider` returns nil; that region stays plain; outer markdown unaffected. |
| Very large document | Viewport-scoped highlighting only (Neon); never full-document restyle. |
| Neon `TextViewHighlighter.init` throws | Caught; `self.highlighter = nil`; plain text + chrome. Never propagate. |

Nothing in this table produces a user-visible error, an empty editor, or a crash.

### 4.9 App-target integration (exact wiring)

- **One `ThemeController`** created in `MacDown2App`/`AppDelegate`, injected into the SwiftUI `Environment` and passed to each `WindowController`. On `NSApplication` appearance change (observe `NSApp.effectiveAppearance` via KVO or `AppDelegate`), call `themeController.setAppearance(...)`.
- **`SyntaxHighlightStore` per window**, created in `WindowController.init` next to `editorStore` (share **one** `GrammarRegistry` across windows — pass it in). After the window's `EditorTextSystem` is created (WindowController already pre-creates it, `WindowController.swift:26`), build the highlighter:
  ```swift
  _ = highlightStore.highlighter(
      for: activeTab.id.uuidString,
      textSystem: system,                       // the just-created EditorTextSystem
      languageID: activeTab.document.format.highlightLanguageID,
      theme: themeController.current
  )
  ```
- **Re-theme:** observe `themeController.current` (Observation) at the app/window level; on change call `highlightStore.applyThemeToAll(themeController.current)` for every window.
- **Teardown:** in `WindowController.windowWillClose` (which already calls `editorStore.evictAll()`), also call `highlightStore.evictAll()`. On single-tab close paths that call `editorStore.evict(id)`, mirror with `highlightStore.evict(id)`.
- **Save As changes format:** when the active document's `format.highlightLanguageID` changes, call the highlighter's `setLanguage(newID)` (drive from the existing document-observation in `WindowController.updateTitleAndEditedState` or a dedicated observer).
- **View menu → Theme submenu** in `WorkspaceCommands`: list `themeController.available`, checkmark the active one, action → `themeController.select(theme)`. Add a `#if DEBUG` **"Cycle Theme"** item (⌃⌥⌘T) that advances through `available` — this is the hook the theme-switch UI test drives (§7.4). No non-DEBUG shortcut is required by the epic.

#### 4.9.1 Permitted (optional) EditorCore change
If, and only if, the pinned Neon version needs the `NSTextView` to exist *before* the SwiftUI view mounts (it does not for the pre-created active-tab system — `WindowController.swift:26` already creates it), no EditorCore change is needed. **Do not** add a highlighter property to `EditorTextSystem` (violates the dependency direction, D1). If you find you need an edit-timing hook that Neon cannot get on its own, add an **additive, optional** `onTextDidChange: ((NSRange) -> Void)?` callback to `EditorTextSystem` and document it — but first confirm Neon's own observation works on our TK2 stack (§10.1). Prefer zero EditorCore change.

### 4.10 Grammar packaging & pinning (exact)

Add to `Package.swift` `dependencies` (pin every one to an exact tag or commit — record the resolved versions in the PR):

```swift
.package(url: "https://github.com/tree-sitter/swift-tree-sitter", from: "0.9.0"),         // SwiftTreeSitter + SwiftTreeSitterLayer
.package(url: "https://github.com/ChimeHQ/Neon", from: "0.6.0"),                          // Neon + TreeSitterClient
.package(url: "https://github.com/tree-sitter-grammars/tree-sitter-markdown", ...),        // tree_sitter_markdown + _inline
.package(url: "https://github.com/tree-sitter/tree-sitter-json", ...),                     // tree_sitter_json
.package(url: "https://github.com/tree-sitter/tree-sitter-html", ...),                     // tree_sitter_html
```

`Highlighting` target `dependencies`: `EditorCore`, `Themes`, and the products
`SwiftTreeSitter`, `SwiftTreeSitterLayer`, `Neon`, `TreeSitterClient`, and each grammar product.
Add `resources: [.copy("Queries")]` to `Highlighting` **only if** you vendor `.scm` files (§4.7).
**Version numbers above are placeholders — resolve the latest compatible tags, verify the exact product/module names and the grammar C entry-point symbols against the resolved packages, pin them, and list the resolved versions in the PR body.** If a grammar has no SPM `Package.swift`, wrap its C sources in a local SPM target under `Packages/MacDownKit/Sources/CGrammar<Lang>/` with a small `module.modulemap` (see §10.4) rather than blocking.

### 4.11 Colour parsing contract (the MPColor port — fully specified)

**Locate the legacy sources in the backup (D4):**
```bash
find legacy-reference -iname "*.style" -o -iname "*.css" | sort           # editor/preview themes
grep -rl "MPColor\|colorFromString\|MPUtilities" legacy-reference          # colour util + tests
find legacy-reference -iname "*ColorTests*" -o -iname "*UtilitiesTests*"    # the tests to port
```

`ThemeColor.init?(cssString:)` MUST accept (case-insensitive, surrounding whitespace trimmed):

| Input form | Rule | Example → RGBA |
|---|---|---|
| `#RGB` | each hex nibble doubled | `#f00` → (1, 0, 0, 1) |
| `#RGBA` | nibbles doubled incl. alpha | `#f008` → (1, 0, 0, 0.533) |
| `#RRGGBB` | two hex per channel | `#00ff00` → (0, 1, 0, 1) |
| `#RRGGBBAA` | + alpha byte | `#0000ff80` → (0, 0, 1, 0.502) |
| `rgb(r,g,b)` | 0–255 ints | `rgb(255,128,0)` → (1, 0.502, 0, 1) |
| `rgba(r,g,b,a)` | a is 0–1 float | `rgba(0,0,0,0.5)` → (0, 0, 0, 0.5) |
| named colour | table ported from legacy `MPColor`/`MPUtilities` | `red` → (1, 0, 0, 1) |
| anything else | **return nil** | `"potato"`, `"#12"`, `""` → nil |

- Leading `#` optional for hex? **No** — require the `#` for hex forms (matches CSS and MPColor). A bare `ff0000` is treated as a name lookup (fails → nil) unless it's in the named table.
- Alpha byte `0x80` → `128/255 = 0.502` (round to 3 dp in tests).
- **Named-colour table:** port the exact entries found in the legacy source. At minimum the 16 CSS/HTML basics (`black,silver,gray,white,maroon,red,purple,fuchsia,green,lime,olive,yellow,navy,blue,teal,aqua`). If the legacy table has more, port them all; if fewer, ship the 16 basics as a superset and note it.
- `ThemesTests.ColorParsingTests` ports every case in the legacy `MPColorTests`/`MPUtilitiesTests` **plus** the table above. This is acceptance bullet 4.

---

## 5. File layout (exact)

```
Packages/MacDownKit/Sources/Themes/
  Themes.swift                 # keep namespace enum OR delete if a real type suffices for lint
  ThemeColor.swift             # ThemeColor + cssString parsing (§4.11)
  TokenStyle.swift             # TokenStyle, EditorChrome, ThemeAppearance
  Theme.swift                  # Theme + style(for:) fallback
  BundledThemes.swift          # loader
  ThemeController.swift        # @Observable controller
  ThemePreferenceStore.swift   # protocol + UserDefaults impl
  Themes/                      # RESOURCES (Bundle.module): <lightID>.json, <darkID>.json
Packages/MacDownKit/Sources/Highlighting/
  Highlighting.swift           # keep/replace stub namespace
  HighlightCaptureName.swift   # canonical set + fallback
  GrammarRegistry.swift        # id → LanguageConfiguration (+ languageProvider), failure-isolated
  SyntaxHighlighting.swift     # protocol
  NeonSyntaxHighlighter.swift  # concrete Neon adapter (+ locationTransformer, styledFont)
  SyntaxHighlightStore.swift   # per-window cache
  Queries/                     # ONLY if vendored (§4.7): markdown/, json/, html/*.scm
Packages/MacDownKit/Tests/ThemesTests/
  ColorParsingTests.swift      # §4.11 — ports MPColorTests + the table
  ThemeTests.swift             # style(for:) fallback; Codable round-trip; bundled themes decode
  ThemeControllerTests.swift   # appearance switch flips current; select persists (temp store)
Packages/MacDownKit/Tests/HighlightingTests/
  GrammarRegistryTests.swift   # known id → config; unknown → nil; failure isolation; injection provider
  HighlightParseTests.swift    # headless SwiftTreeSitter parse + query captures (markdown/json/html)
  HighlightInjectionTests.swift# markdown fenced ```swift/```json injection captures via LanguageLayer
  HighlightPerformanceTests.swift # §7.3 gates (full 1 MB, incremental keystroke) — swift test
  CaptureFallbackTests.swift   # HighlightCaptureName.fallback chain
  Fixtures.swift               # deterministic N-MB markdown/json generators
App target:
  MacDown2/MacDown2App.swift          # create ThemeController; observe NSApp.effectiveAppearance
  MacDown2/WindowController.swift     # own SyntaxHighlightStore; attach on init; evict on close; setLanguage
  MacDown2/WorkspaceShellView.swift   # thread themeController/highlightStore if needed
  MacDown2/WorkspaceCommands.swift    # View ▸ Theme submenu + DEBUG "Cycle Theme"
  MacDown2UITests/HighlightingUITests.swift  # visual: open fixtures, cycle theme, assert recolor
Package.swift                          # + deps (§4.10), Themes resources, Highlighting deps/resources
MacDown2/project.yml                   # only if a new linked product/arg is added (see §6)
.github/workflows/ci.yml               # see §6 — likely NO change; confirm SPM fetch on runner
```

## 6. Build-config changes (exact)

- **`Package.swift`:** add the 5 package deps (§4.10); give `Themes` `resources: [.process("Themes")]`; give `Highlighting` its new target deps (+ `resources: [.copy("Queries")]` if vendored). `ThemesTests` gains no new dep; `HighlightingTests` already depends on `Highlighting`.
- **`project.yml`:** `MacDown2` already links `Themes` and `Highlighting` products — **no dependency edit needed**. Add nothing unless you introduce a new launch arg target setting. Regenerate with `xcodegen generate`.
- **`ci.yml`:** the existing `swift build && swift test` + UI-test build steps already cover this epic. **Confirm the `macos-15` runner can resolve the new SPM package graph over the network** (grammars are fetched at resolve time). If resolution is slow/flaky, cache `~/Library/Caches/org.swift.swiftpm` — flag on the PR, do not silently add unpinned deps. Do **not** add an `xcodebuild test` run step (§1.6).

## 7. Test plan (mapped to issue #6 acceptance)

Fakes/fixtures: `FakeThemePreferenceStore` (in-memory), temp-dir `UserDefaultsThemePreferenceStore(suiteName:)`, deterministic N-MB source generators.

- **7.1 Location transform (`swift test`)** — `locationTransformer` maps offsets → `(row,column)` correctly across multi-byte and multi-line input (UTF-16 columns). Guards injections/multiline.
- **7.2 Lifecycle / leak (`swift test`, may need `@MainActor`)** — `SyntaxHighlightStore.highlighter` caches; `evict` → `tearDown` → **weak ref to the highlighter (and, via it, no retained text-view graph) is nil**. Mirrors E04's evict test.
- **7.3 Parse-layer performance (`swift test` — the CI-enforced gates):**
  | Test | Budget | Method |
  |---|---|---|
  | `fullHighlight1MB` | **< 500 ms** | 1 MB fixture; `Parser.parse(.utf16)` + run `highlights` query + collect captures; `ContinuousClock().measure`. |
  | `incrementalKeystroke1MB` | **< 50 ms** | after full parse, apply a 1-char `InputEdit` + `tree.edit` + reparse with old tree + re-query changed range only. |
  | `mainThreadParseBudget` | **< 8 ms** (documented) | the synchronous slice tree-sitter needs for one incremental edit on 1 MB; assert + record the CI number. Full XCTMetric version lives in the manual Instruments cross-check. |
  Budgets are **provisional** — calibrate on the runner, apply *documented* headroom, never loosen silently. Log+skip (don't pass) if a fixture can't build.
- **7.4 Visual pipeline (XCUITest, `build-for-testing` in CI, run locally on macOS 26):** launch `-UITesting -openFiles fixture.md` (reuse E03 hooks); assert highlight attributes appear; trigger DEBUG **Cycle Theme** and assert the background/foreground colour changes **without** content reflow (proxy for "recolor without reparse"); edit inside a ```swift fence and assert only nearby styling changes.
- **7.5 Colour/theme (`swift test`):** `ColorParsingTests` (§4.11, ports `MPColorTests` — acceptance bullet 4); `ThemeTests` (fallback, Codable round-trip, both bundled themes decode + define every canonical root); `ThemeControllerTests` (appearance flips `current`; `select` persists via temp store).
- **7.6 Registry (`swift test`):** every registered id → non-nil config; unknown id → nil; a deliberately-broken config path → nil (not a throw); `languageProvider` resolves `markdown_inline` + MVP fence languages, returns nil for unknown.

**Acceptance map (issue #6):** bullet 1 → 7.3 `incrementalKeystroke` + 7.4 fence edit; bullet 2 → 7.4 theme cycle; bullet 3 → 7.6 + 7.4 open-every-format; bullet 4 → 7.5 `ColorParsingTests`; bullet 5 → 7.3 `mainThreadParseBudget` + Instruments cross-check.

## 8. Implementation order (package first, app second — suite green before app)

1. **Themes model:** `ThemeColor` + parsing → `ColorParsingTests` green (port `MPColorTests` from `legacy-reference`).
2. `TokenStyle`/`EditorChrome`/`ThemeAppearance` → `Theme` + `style(for:)` fallback → `ThemeTests`.
3. Author the **2 shipped JSON themes** (one light, one dark) by porting the chosen `legacy-reference` `.style` files onto the §4.4 capture set; `BundledThemes` loads them.
4. `ThemePreferenceStore` + `ThemeController` → `ThemeControllerTests`.
5. `HighlightCaptureName` + `GrammarRegistry` (markdown+inline, json, html) → `GrammarRegistryTests`, `CaptureFallbackTests`.
6. Headless parse/injection tests → `HighlightParseTests`, `HighlightInjectionTests`.
7. `HighlightPerformanceTests` — **must be green via `swift test`** (§7.3).
8. `SyntaxHighlighting` protocol + `NeonSyntaxHighlighter` + `SyntaxHighlightStore` → lifecycle/leak test (§7.2).
9. **App wiring:** `ThemeController` in `MacDown2App`; per-window `SyntaxHighlightStore` in `WindowController`; attach/evict/setLanguage; View ▸ Theme submenu + DEBUG Cycle Theme.
10. `HighlightingUITests` (+ `xcodegen generate`; runs under the existing UI-test build step).
11. Validate (§9); manual acceptance pass; mark PR ready.

**The package suite must be green before you touch the app target.**

## 9. Validation (must all pass before review)

```bash
cd MacDown2/Packages/MacDownKit && swift build && swift test          # all green incl. §7 (headless)
cd ../../.. && swiftformat --lint MacDown2 && swiftlint lint --strict MacDown2
cd MacDown2 && xcodegen generate
xcodebuild -project MacDown2.xcodeproj -scheme MacDown2 -destination 'platform=macOS' build build-for-testing
xcodebuild -project MacDown2.xcodeproj -scheme macdown2 -destination 'platform=macOS' build
# Locally on macOS 26 only (NOT CI): xcodebuild ... test   → runs HighlightingUITests
```

## 10. Open decisions (flag on the PR — do not silently resolve)

1. **Neon ↔ E04 TK2 stack edit observation.** Confirm Neon's `TextViewHighlighter` observes edits on our plain-`NSTextView`+`NSTextContentStorage` stack without owning the `NSTextView.delegate` (EditorCore owns that). If it needs an edit-timing hook, use the §4.9.1 additive callback — don't take the delegate. Report what you found.
2. **Perf budgets vs CI hardware.** 50 ms / 500 ms / 8 ms are dev-machine targets; calibrate on `macos-15` and record measured numbers with documented headroom.
3. **SPM grammar availability & CI network.** If any grammar lacks an SPM package or the runner can't resolve/build it, wrap its C sources locally (§10.4 / §4.10) and pin — flag which grammars needed it.
4. **`legacy-reference/` size.** Un-ignoring the whole backup may bloat the repo. If large, propose committing only the theme/CSS + colour-test subset the port needs (owner decides). Flag before syncing gigabytes.
5. **Which legacy themes ship (decision O4 from the epic).** Pick one light + one dark from the backup and name them in the PR; the model is validated by 2 themes, more can follow.
6. **`AGENTS.md` still says `rewrite/main`** and one-branch-per-epic → PR into `rewrite/main`; the repo moved to `master`. Propose the one-line fix in this PR or a follow-up — owner decides (do not rewrite silently).

## 11. Hand-off notes / known pitfalls (condensed — mirrored to the PR inline comment)

- **Dependency direction is law:** `Highlighting → EditorCore`/`Themes`, never the reverse. The highlighter attaches from outside via `EditorTextSystem.textView`; it is **not** a property of `EditorTextSystem` (D1, §4.1).
- **Recolour ≠ reparse.** Theme change = re-run the `attributeProvider` over the visible range (`invalidate(.all)`); the tree is untouched (D5, §4.3). If you find yourself reparsing on theme switch, stop.
- **Graceful degradation is tested, not assumed.** Unknown/failed language ⇒ plain text + chrome, never an error (§4.8, §7.6).
- **Perf gates live in `HighlightingTests` (`swift test`)** on the SwiftTreeSitter parse layer, because `xcodebuild test` can't run on the CI runner (§1.6, §7.3). The Neon+NSTextView path is XCUITest, build-for-testing only.
- **Two markdown grammars.** `markdown` + `markdown_inline`, with fence injection through `languageProvider`; unknown fence ⇒ plain (§4.7).
- **`Theme` never stores `NSColor`** (breaks Codable/Sendable); bridge at apply time with explicit **sRGB** (§4.2).
- **Read the real themes** from `legacy-reference/`; don't invent colours (D4). If the backup isn't in your checkout, flag it — don't fabricate.
- **Pin every new dependency** to an exact tag/commit and list resolved versions in the PR (§4.10).
- **Keystroke echo & viewport laziness** carry over from E04: never force whole-document layout/highlight on open; let Neon drive the viewport.
