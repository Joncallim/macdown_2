# EPIC-13 implementation architecture: Settings

Baseline `master` SHA: `f61fe75eee9cc3c43b59e424245dfc15380e1d80` (merge of #51,
2026-08-22). Product contract: GitHub issue #14.

---

## 1. Owner summary

**What changes for the user?** MacDown 2 gets a real Settings window (`⌘,`,
`MacDown 2 → Settings…`) with five panes — General, Editor, Markdown, Preview
& Export, and Formats. Today almost everything these panes will control is a
hard-coded constant somewhere in the app: the editor font is always the
system monospaced font, indentation is always 4 spaces, every editing assist
is always on for Markdown files, new documents always default to a 50/50
split preview, and the export panel always opens on "Standalone HTML,
Embedded CSS" no matter what you exported last. None of that is wrong today,
but none of it is a choice the user gets to make and have remembered either.

**Why now?** E13 is the last unstarted item in the `formats/export/settings`
bucket that the roadmap places before E14 (`planning/epics/README.md`). Its
only dependency, E02 (workspace shell), has been done since M1. Nothing
downstream needs Settings, but Settings needs nothing downstream either —
there is no reason to defer it further, and every epic after this one
(E14 text filters, E19 math, E20 diagrams) will eventually want a place to
put its own preferences, so it is better to establish the pattern now while
the number of preferences is still small enough to get right.

**Main technical approach.** MacDown 2 already has three small, independent,
`UserDefaults`-backed preference stores — `Themes.ThemeController`,
`FileTree.FileTreePreferences`, `Workspace.WorkspaceStateStore` — each owned
by the module whose concern it is, each following the same shape: a
`Codable` value type, a narrow storing protocol, a `UserDefaults`-backed
implementation that accepts an injectable suite for test isolation, and (for
the two that are `@Observable`) a `@MainActor` controller class constructed
once in `AppDelegate` and threaded through the app via SwiftUI's
environment. This epic does not invent a new pattern. It adds a fourth store
of the same shape — `AppSettings.AppSettingsModel` — for the preference
domains that do not already have an owner (editor typography/behaviour,
the one Markdown parsing toggle that is actually wired today, default
preview layout, default export choices, default new-document encoding), and
it builds a SwiftUI `Settings` scene whose five panes read and write that
model plus the three existing stores where their preferences already live.
Because every pane binds directly to `@Observable` state and every
consumer (the editor split view, the export panel, `AppDelegate`'s launch
logic) reads that same state through SwiftUI's environment or a plain
reference, "changes apply live" falls out of the architecture rather than
requiring a manual notification mechanism.

**Main risks or compromises.**

1. The epic issue describes migrating "~50 MPPreferences keys" from the
   original ObjC MacDown. That legacy source is not present in this
   repository (see §2) — `legacy-reference/` does not exist on this branch,
   despite `MIGRATION_PLAN.md` describing it as tracked. This architecture
   does not fabricate a key list it cannot verify. Old-preferences import
   (open decision O3) is narrowed to a detection-only stub with a named
   follow-up; see §2 and §18.
2. `MarkdownParseOptions` already exists with six toggles, but
   swift-markdown 0.8.0 only actually honours one of them
   (`blockDirectives`); the other five are always on regardless of their
   value (see the type's own doc comment, quoted in §2). The Markdown pane
   in this epic exposes only the one toggle that does something. Shipping
   five controls that silently do nothing would be a worse outcome than
   shipping four fewer controls.
3. Export template/layout/resource-root/budget/metadata-policy are
   explicitly fixed by the export composer (`ExportRequest`'s own doc
   comment says as much) and stay that way — this epic does not add
   template selection. The Preview & Export pane's scope is limited to
   defaults for choices that are already per-export, user-facing, and
   independent of the composer's fixed pipeline (export format, CSS
   embedding style, default preview layout for new tabs).

**What is deliberately not being built.**

- Update-channel preferences (Sparkle) — E17.
- Any plugin/extension/text-filter preferences — E14.
- A font/theme *editor* — the Theme pane reuses the existing theme picker
  (`ThemeController`); building or importing new themes is O4/E07 scope, not
  E13.
- Toggles for the five non-functional `MarkdownParseOptions` fields.
- Export template selection, export resource budgets, or any other
  composer-owned export input.
- A general-purpose, user-editable format↔extension mapping. The Formats
  pane is read-only informational content plus one new, narrowly-scoped
  default-encoding preference (§7, §9).
- Full old-MacDown preference import (O3) — narrowed to a detection stub;
  see §18.

---

## 2. Baseline and repository reconciliation

### 2.1 What already exists and must be reused, not duplicated

Three preference stores already ship, and this epic's design is explicitly
modelled on all three:

| Store | Module | Shape | Suite |
|---|---|---|---|
| `ThemePreferenceStoring` / `UserDefaultsThemePreferenceStore` / `ThemeController` | `Themes` | `@MainActor @Observable` controller wraps a protocol-backed store; controller is the single source of truth for `light`/`dark`/`current` | `UserDefaults.standard` (or injected suite) |
| `FileTreePreferenceStoring` / `UserDefaultsFileTreePreferenceStore` / `FileTreePreferences` | `FileTree` | Same shape; additionally exposes a manual `addObserver`/`removeObserver` callback list for non-SwiftUI (AppKit) consumers | `UserDefaults.standard` (or injected suite) |
| `WorkspaceStateStoring` / `WorkspaceStateStore` | `Workspace` | Struct-only store (no `@Observable` controller — `WorkspaceModel` reads it directly); explicitly documented as **not** a user preference | dedicated suite `com.joncallim.macdown2.workspace` |

`WorkspaceStateStore.swift` carries this exact sentence, written in
anticipation of this epic:

> This is intentionally separate from user preferences (`AppSettings`, E13):
> sidebar visibility is window state, not a user setting.

That is the deciding precedent for two things this architecture commits to:
(a) genuine user preferences belong in `UserDefaults.standard`, matching
`ThemeController`/`FileTreePreferences`, not a dedicated suite; window/UI
state is what gets its own suite, and Settings owns none of that; (b) a
per-module store stays owned by its module. `AppSettings` does not absorb
`ThemeController`'s or `FileTreePreferences`' storage — the Settings *UI*
presents them, but does not re-own them.

`AppDelegate.init` already isolates all `UserDefaults`-backed state under
UI testing:

```swift
let suite = "com.joncallim.macdown2.uitest.\(UUID().uuidString)"
defaults = UserDefaults(suiteName: suite) ?? .standard
defaults.removePersistentDomain(forName: suite)
```

`fileTreePreferences` and `workspaceStateStore` are both constructed from
this isolated `defaults` instance under `-UITesting`. Any new
`AppSettingsModel` must be constructed the same way — from the same
`defaults` variable — or XCUITests will read/write the developer's real
`~/Library/Preferences/com.joncallim.macdown2.plist`.

`MarkdownEngine/MarkdownParseOptions.swift` already carries a doc comment
addressed directly to this epic:

> The struct is kept as the stable shape that E12 (export) and E13
> (settings) will consume... The other five options (`tables`, `taskLists`,
> `strikethrough`, `autolinks`, `footnotes`) record intent for E12/E13 but
> are always on regardless of their flag values, because swift-markdown
> enables them together with GFM.

This is verified, not assumed — `ParseEngine.swift` was inspected and only
`blockDirectives` maps to a real `ParseOptions` flag
(`.parseBlockDirectives`); the other five fields are carried but unused by
the parser. This is why §1 and §9 scope the Markdown pane to one toggle.

`EditorCore/EditorConfiguration.swift` and
`EditorCore/EditingAssistConfiguration.swift` are already fully-typed,
`Sendable`, `Equatable` value types with sensible defaults
(`EditorConfiguration.default`, `.markdownDefault`/`.disabled`). The one and
only place they are constructed today is
`DocumentEditorSplitView.editorConfiguration` in the app target:

```swift
private var editorConfiguration: EditorConfiguration {
    var config = EditorConfiguration.default
    config.scrollsPastEnd = false
    config.editingAssists = document.format.id == "markdown" ? .markdownDefault : .disabled
    return config
}
```

This is a computed property on a SwiftUI `View`, recomputed on every body
re-evaluation. It is the exact seam this epic threads `AppSettings` through
— no new observation mechanism is needed, because a change to an
`@Observable` `AppSettingsModel` read inside this computed property already
invalidates and re-renders every open tab's split view.

`ExportPanelView.swift`'s `ExportSelectionModel` is constructed fresh, with
hard-coded defaults, every time the export panel opens:

```swift
@MainActor @Observable
final class ExportSelectionModel {
    var format: ExportFormatOption = .standaloneHTML
    var style: ExportStyleEmbedding = .embedded
}
```

This is the legitimate, composer-independent seam for a "remember/default
my export choice" preference — it does not touch `ExportRequest`,
`ExportComposer`, or the template layer, all of which are explicitly fixed
(`ExportRequest.swift`'s own doc comment: *"No layout, resource-root,
budget, metadata-policy, or template identity may be supplied — those are
fixed by the composer."*). This epic reads that sentence as binding and
does not propose changing it.

`FileCore/FileFormat.swift` (`FileFormatRegistry.defaultFormats`) and
`FileCore/FormatManifest.swift` are a matched, drift-checked pair —
`FormatRegistryConsistencyTests` fails if they disagree. Neither is
user-editable today, and this epic does not make them so; §7's Formats pane
is read-only over this data plus one new preference (default encoding for
new documents) that does not touch the registry at all.
`FileCore/FileStore.swift` already has `static let defaultEncoding:
String.Encoding = .utf8`, which is the one existing hook this epic
generalises into a preference (§7).

`Package.swift` already declares the `AppSettings` library target and an
empty `AppSettingsTests` test target (`.target(name: "AppSettings")`,
`.testTarget(name: "AppSettingsTests", dependencies: ["AppSettings"])`).
`Sources/AppSettings/AppSettings.swift` is a one-line module stub
(`public enum AppSettings { public static let moduleName = "AppSettings" }`)
with no real content yet. This epic is the first to add real source to
that target.

### 2.2 Stale assumptions reconciled

- **`legacy-reference/` does not exist on this branch, but the source it
  would have held is reachable and has since been inspected directly.**
  `MIGRATION_PLAN.md` §7 states "the legacy ObjC app survives only as
  read-only porting source in `legacy-reference/`", and a filesystem search
  of this repository at the recorded baseline found no such directory.
  Mid-review, the original app's public repository
  (`github.com/MacDownApp/macdown`) was cloned read-only
  (`/home/user/macdownapp/macdown` in the session that wrote this doc) and
  `MacDown/Code/Preferences/MPPreferences.h` — the actual ~45-property
  `PAPreferences` subclass issue #14 refers to — was read directly.
  **Reconciliation:** this confirms the domain boundaries chosen in §2.1/§6
  independently (every field this epic scoped in has a real legacy
  counterpart: `editorConvertTabs`, `editorCompleteMatchingCharacters`,
  `editorSmartHome`, `editorAutoIncrementNumberedLists` ↔
  `EditorSettings`'s assist toggles; `supressesUntitledDocumentOnLaunch` ↔
  `GeneralSettings.launchBehavior`; `extensionTables`/`extensionFootnotes`/
  `extensionStrikethough`/`extensionAutolink` ↔ the four inert
  `MarkdownParseOptions` fields). It also surfaces legacy preferences this
  epic does **not** scope in, each with a real, already-typed-but-unexposed
  counterpart already living in MacDownKit: `editorSyncScrolling` (no
  toggle exists anywhere in `Preview.ScrollSyncController` today),
  `editorHorizontalInset`/`editorVerticalInset`/`editorLineSpacing` (map
  directly to `EditorConfiguration.textInsets`/`.lineHeightMultiple`, typed
  and constructed but never settings-driven), `editorScrollsPastEnd` (typed
  on `EditorConfiguration` but currently force-set to `false` at the one
  call site, §2.1), `editorEnsuresNewlineAtEndOfFile`,
  `editorUnorderedListMarkerType`, `editorShowWordCount`/
  `editorWordCountType`, and `htmlDefaultDirectoryUrl` (a default export
  destination folder). None of these were part of issue #14's five named
  panes or this epic's five implementation slices (§17), and the decision
  discussed in this review round is to leave the epic's scope exactly as
  written rather than reopen it for these — they are recorded here, with
  their real legacy property names, specifically so a later small
  slice/epic does not have to re-derive this list from scratch. The old
  Hoedown-era extension flags with no GFM equivalent at all
  (`extensionUnderline`, `extensionSuperscript`, `extensionHighlight`,
  `extensionQuote`, `extensionSmartyPants`) and everything math/diagram/
  update-channel-scoped (`htmlMathJax*`, `htmlGraphviz`, `htmlMermaid`,
  `updateIncludesPreReleases`) are out of scope for a different reason —
  they belong to E19/E20/E21/E17 respectively, not to a source-availability
  gap.
- **Open decision O3** ("Import old MacDown prefs/themes on first run?") is
  no longer blocked on source availability (the key list above exists), but
  actually mapping and importing ~45 legacy keys — several of which
  (`editorStyleName`, `htmlHighlightingThemeName`, `htmlTemplateName`) name
  concepts (themes, templates) that do not correspond 1:1 to MacDown 2's
  current, deliberately-narrowed equivalents — is real, separate work this
  review round chose to keep out of this epic. This epic ships the
  detection half only — on first launch, check whether
  `UserDefaults(suiteName: "com.uranusjr.macdown")` (the original MacDown's
  bundle ID) has a persistent domain at all — and if so, record that fact
  for a future epic to act on, rather than silently doing nothing and
  rather than guessing at key names under time pressure. Full detail in
  §18.
- **Issue #14's "Font/theme pickers integrate with the theme system
  (E05/E07)" acceptance criterion** is satisfied by the Theme pane
  presenting the *existing* `ThemeController`, not by Settings owning a new
  theme concept.

### 2.3 Dependencies and follow-ups this epic intersects

- No open bug tracker issues reference E13 directly (`#34`, `#35` are E08/
  content-parsing scoped and unrelated).
- `RELEASE_HARDENING.md` mentions "preferences" only in the context of
  E17's development→release *namespace* migration (moving
  `com.joncallim.macdown2` to whatever the frozen public identity becomes).
  That is E17's job. This epic's only obligation toward it is to keep keys
  few, typed, and namespaced under one JSON blob per domain (§6) rather
  than dozens of loose top-level keys, so a future migration has a small,
  enumerable surface to move.

---

## 3. User journeys

**J1 — Change the editor font and see it everywhere immediately.**
The user opens Settings (`⌘,`), goes to Editor, changes the font from the
default system monospaced font to Menlo 13pt. Every open tab's editor
re-renders in the new font without needing to switch tabs, close the
window, or restart the app. A new tab opened afterward also uses Menlo 13.
Quitting and relaunching preserves the choice.

**J2 — Turn off an editing assist that is getting in the way.**
The user finds automatic bracket-pairing intrusive while writing Markdown
that includes a lot of literal parentheses. They open Settings → Editor and
turn off "Complete matching characters." The next keystroke in any open
Markdown tab stops pairing; other assists (list continuation, Tab-to-indent)
remain on because they were not turned off. A non-Markdown tab (e.g. JSON)
is unaffected either way, because assists are format-gated independently of
this preference (§9's non-negotiable invariant carries this forward
unchanged).

**J3 — Set a default export format and have the export panel remember it.**
The user regularly exports to self-contained HTML. They open Settings →
Preview & Export and set "Default export format" to "Self-contained HTML."
The next time they press `⌘⇧E`, the export panel opens with "Self-contained
HTML" already selected instead of the previous hard-coded "Standalone
HTML." They can still change it for that one export without changing the
default; the panel's own picker is unaffected in behaviour, only its
initial value changed.

**J4 — Recover from a corrupted or hand-edited preferences file.**
A user (or a bug, or a `defaults write` typo) leaves
`com.joncallim.macdown2`'s `appSettings.editor` key holding a JSON blob
that no longer matches `EditorSettings`'s shape, or a font family name that
no font on the system provides. On next launch, Settings silently falls
back to `EditorSettings.default` for the fields that failed to decode
(whole-domain fallback, not partial field recovery — see §9) rather than
crashing, and the font resolution step falls back to the system monospaced
font rather than producing no font at all. The user sees defaults, not an
error dialog, and can immediately re-pick their preferred font.

**J5 — First launch after upgrading from an installation that predates
Settings.** No `appSettings.*` keys exist yet. Every pane shows the
documented defaults (system monospaced font, 4-space indent, all
functional assists on, split preview, Standalone HTML/Embedded CSS export,
UTF-8 for new documents) — the same values `EditorConfiguration.default`,
`EditingAssistConfiguration.markdownDefault`, `PreviewLayoutMode.
defaultMode`, `ExportSelectionModel`'s current hard-coded initial values,
and `FileStore.defaultEncoding` already produce today. Nothing observably
changes for an existing user until they open Settings and make a choice.

---

## 4. Non-negotiable invariants

1. **Live apply, no relaunch.** Every setting takes effect on already-open
   tabs/windows without requiring the user to close and reopen anything
   (issue #14's own acceptance criterion). This is achieved structurally
   (§8), not by a manual "apply" button or a restart prompt.
2. **Existing document fidelity is untouched.** No setting introduced here
   rewrites the encoding, BOM, line endings, or content of an
   already-open or already-saved document (D10). The new default-encoding
   preference (§7) only changes the default parameter used the next time a
   *new, untitled* document is saved for the first time.
3. **No fake controls.** A Settings toggle must correspond to code that
   actually branches on it. The five non-functional `MarkdownParseOptions`
   fields do not get UI in this epic (§2.1, §9).
4. **The export composer's fixed contract is not reopened.** Template,
   layout, resource-root, budget, and metadata-policy stay owned by
   `ExportComposer`/`BuiltInExportTemplate` exactly as documented today.
   This epic only seeds `ExportSelectionModel`'s two already-mutable,
   already-per-export fields.
5. **`FileFormatRegistry`/`FormatManifest` stay authoritative and
   unedited.** Nothing in Settings can desynchronise them from each other
   or from `project.yml`'s declared document types.
6. **No new preference store bypasses UI-test isolation.** Every
   `UserDefaults`-backed read/write introduced by this epic goes through a
   store that accepts an injected suite, and `AppDelegate` wires the same
   isolated `defaults` instance used for `fileTreePreferences`/
   `workspaceStateStore` under `-UITesting`.
7. **Offline/local only (D9).** No preference, including the O3 detection
   stub (§18), performs a network request or reads/writes outside the
   sandboxed-equivalent app-owned locations (`UserDefaults`, the app's own
   Application Support directory if ever needed — not required by this
   epic's scope).
8. **A settings read never blocks the main actor** on I/O beyond a
   synchronous `UserDefaults` access (already the pattern for all three
   existing stores; no epic-13 preference is large enough to justify
   anything else).

---

## 5. Ownership and dependency boundaries

**`AppSettings` (SwiftPM target, already declared) owns:**

- The five preference-domain value types (`GeneralSettings`,
  `EditorSettings`, `MarkdownSettings`, `PreviewExportSettings`,
  `FormatSettings` — §6) and their JSON persistence.
- `AppSettingsStoring` (protocol) and `UserDefaultsAppSettingsStore`
  (concrete implementation).
- `AppSettingsModel` (`@MainActor @Observable` controller, the single
  source of truth other layers read).
- The O3 detection stub (`LegacyPreferencesDetector`, §18).

**`AppSettings` explicitly does not own** (and must not import/depend on):
`Themes` (theme storage stays in `ThemeController`), `FileTree` (folder
browser preferences stay in `FileTreePreferences`), `Workspace` (window
state stays in `WorkspaceStateStore`), `EditorCore`, `MarkdownEngine`,
`Preview`, `ExportService`. `AppSettings` has exactly one internal
dependency: `Foundation`. This mirrors `Themes`' and (mostly) `FileTree`'s
existing leaf-module position — the type *shapes* Settings needs to expose
(fonts, indentation widths, booleans, enums-as-strings) are all expressible
without importing the modules that later *consume* them. The App target is
the layer allowed to import both `AppSettings` and whichever module a given
pane's value feeds (exactly as it already imports both `Themes` and
`EditorCore` today).

**App target (`MacDown2/MacDown2`) owns:**

- The `Settings { }` scene and its five pane views.
- Constructing one `AppSettingsModel` in `AppDelegate`, alongside the
  existing controllers, using the same UI-testing-isolated `defaults`.
- Injecting it into the SwiftUI environment (`\.appSettings`), matching
  `\.themeController`/`\.windowCoordinator`.
- The specific call sites that translate an `AppSettings` value into a
  MacDownKit type: `DocumentEditorSplitView.editorConfiguration` (Editor
  pane → `EditorConfiguration`/`EditingAssistConfiguration`),
  `ExportPanelView`'s panel-open call site (Preview & Export pane →
  `ExportSelectionModel`'s initial values), the new-tab preview-layout
  default (Preview & Export pane → replaces the hard-coded
  `PreviewLayoutMode.defaultMode` read, §9), `AppDelegate`'s launch
  decision (General pane → session-restore vs. new-document), and the
  save-panel/new-document encoding default (Formats pane →
  `FileStore.defaultEncoding` call site).
- `MarkdownParseSession`'s construction (Markdown pane → the one real
  `blockDirectives` toggle).

No new cross-module dependency is introduced in `MacDownKit`: `AppSettings`
gains no new imports, and no existing module gains a dependency on
`AppSettings` (only the App target does — matching how only the App target
depends on `Themes`, `EditorCore`, and `ExportService` simultaneously
today).

---

## 6. Types and interfaces

All new types live in `MacDown2/Packages/MacDownKit/Sources/AppSettings/`
unless noted. Every domain struct is `Codable, Sendable, Equatable` with a
`public static let default` that reproduces MacDown 2's *current* hard-coded
behaviour exactly (§3, J5).

```swift
// GeneralSettings.swift
public struct GeneralSettings: Codable, Sendable, Equatable {
    public enum LaunchBehavior: String, Codable, Sendable {
        case restorePreviousSession
        case startWithNewDocument
    }
    public var launchBehavior: LaunchBehavior
    // Folder-browser prefs are NOT duplicated here — FileTreePreferences
    // already owns opensOnSingleClick/filter (see §5). The General pane UI
    // reads/writes FileTreePreferences directly.

    public init(launchBehavior: LaunchBehavior = .restorePreviousSession) {
        self.launchBehavior = launchBehavior
    }
    public static let `default` = GeneralSettings()
}

// FontDescriptor.swift
// NSFont is not Codable. This is the serializable proxy; conversion to/from
// NSFont happens only at the AppSettings/AppKit boundary (mirrors how
// ThemeColor <-> NSColor bridges only via a computed property).
public struct FontDescriptor: Codable, Sendable, Equatable {
    public var familyName: String
    public var size: Double

    public init(familyName: String, size: Double) {
        self.familyName = familyName
        self.size = size
    }

    /// The family/size pair backing `EditorConfiguration.default`'s font
    /// (`NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight:
    /// .regular)`), recorded as a resolvable family name so this struct
    /// does not need to import AppKit to define its default.
    public static let systemMonospacedDefault = FontDescriptor(
        familyName: "SF Mono", size: 13
    )
}

// EditorSettings.swift
public struct EditorSettings: Codable, Sendable, Equatable {
    public var font: FontDescriptor
    public var wrapsLines: Bool
    public var showsInvisibles: Bool
    public var indentationWidth: Int              // clamped 1...8, matches EditingAssistConfiguration
    public var assistsEnabled: Bool                // maps to EditingAssistConfiguration.isEnabled
    public var continuesMarkdownPrefixes: Bool
    public var completesMatchingCharacters: Bool
    public var convertsTabsToSpaces: Bool
    public var smartHome: Bool
    public var autoIncrementOrderedLists: Bool

    public init(
        font: FontDescriptor = .systemMonospacedDefault,
        wrapsLines: Bool = true,
        showsInvisibles: Bool = false,
        indentationWidth: Int = 4,
        assistsEnabled: Bool = true,
        continuesMarkdownPrefixes: Bool = true,
        completesMatchingCharacters: Bool = true,
        convertsTabsToSpaces: Bool = true,
        smartHome: Bool = true,
        autoIncrementOrderedLists: Bool = true
    ) {
        self.font = font
        self.wrapsLines = wrapsLines
        self.showsInvisibles = showsInvisibles
        self.indentationWidth = min(max(1, indentationWidth), 8)
        self.assistsEnabled = assistsEnabled
        self.continuesMarkdownPrefixes = continuesMarkdownPrefixes
        self.completesMatchingCharacters = completesMatchingCharacters
        self.convertsTabsToSpaces = convertsTabsToSpaces
        self.smartHome = smartHome
        self.autoIncrementOrderedLists = autoIncrementOrderedLists
    }
    public static let `default` = EditorSettings()
}

// MarkdownSettings.swift
public struct MarkdownSettings: Codable, Sendable, Equatable {
    /// The only `MarkdownParseOptions` field swift-markdown 0.8.0 actually
    /// honours today. See §2.1/§9 for why the other five are not exposed.
    public var parsesBlockDirectives: Bool

    public init(parsesBlockDirectives: Bool = true) {
        self.parsesBlockDirectives = parsesBlockDirectives
    }
    public static let `default` = MarkdownSettings()
}

// PreviewExportSettings.swift
public struct PreviewExportSettings: Codable, Sendable, Equatable {
    public enum DefaultPreviewLayout: String, Codable, Sendable {
        case editorOnly, split, previewOnly
    }
    public enum DefaultExportFormat: String, Codable, Sendable {
        case standaloneHTML, selfContainedHTML, pdf
    }
    public enum DefaultExportStyle: String, Codable, Sendable {
        case embedded, linked
    }

    public var defaultPreviewLayout: DefaultPreviewLayout
    public var defaultExportFormat: DefaultExportFormat
    public var defaultExportStyle: DefaultExportStyle

    public init(
        defaultPreviewLayout: DefaultPreviewLayout = .split,
        defaultExportFormat: DefaultExportFormat = .standaloneHTML,
        defaultExportStyle: DefaultExportStyle = .embedded
    ) {
        self.defaultPreviewLayout = defaultPreviewLayout
        self.defaultExportFormat = defaultExportFormat
        self.defaultExportStyle = defaultExportStyle
    }
    public static let `default` = PreviewExportSettings()
}

// FormatSettings.swift
public struct FormatSettings: Codable, Sendable, Equatable {
    /// Applies only to a document that has never been saved before this
    /// preference is read (D10 — never retroactive).
    public var defaultEncodingForNewDocuments: String   // IANA name, e.g. "utf-8"

    public init(defaultEncodingForNewDocuments: String = "utf-8") {
        self.defaultEncodingForNewDocuments = defaultEncodingForNewDocuments
    }
    public static let `default` = FormatSettings()
}
```

```swift
// AppSettingsStoring.swift
@MainActor
public protocol AppSettingsStoring: Sendable {
    var general: GeneralSettings { get set }
    var editor: EditorSettings { get set }
    var markdown: MarkdownSettings { get set }
    var previewExport: PreviewExportSettings { get set }
    var formats: FormatSettings { get set }
}

// UserDefaultsAppSettingsStore.swift
@MainActor
public struct UserDefaultsAppSettingsStore: AppSettingsStoring {
    private let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var general: GeneralSettings {
        get { load(.general) }
        set { save(newValue, key: .general) }
    }
    public var editor: EditorSettings {
        get { load(.editor) }
        set { save(newValue, key: .editor) }
    }
    public var markdown: MarkdownSettings {
        get { load(.markdown) }
        set { save(newValue, key: .markdown) }
    }
    public var previewExport: PreviewExportSettings {
        get { load(.previewExport) }
        set { save(newValue, key: .previewExport) }
    }
    public var formats: FormatSettings {
        get { load(.formats) }
        set { save(newValue, key: .formats) }
    }

    /// Whole-domain fallback on any decode failure (missing key, type
    /// mismatch, or a shape the current app version no longer understands) —
    /// never a partially-decoded value (J4).
    private func load<T: Codable>(_ key: Key) -> T where T: HasDefault {
        guard let data = defaults.data(forKey: key.rawValue),
              let value = try? JSONDecoder().decode(T.self, from: data)
        else { return T.defaultValue }
        return value
    }

    private func save(_ value: some Codable, key: Key) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key.rawValue)
    }

    private enum Key: String {
        case general = "appSettings.general"
        case editor = "appSettings.editor"
        case markdown = "appSettings.markdown"
        case previewExport = "appSettings.previewExport"
        case formats = "appSettings.formats"
    }
}

/// Lets `load(_:)` above be generic over the five domain types without
/// repeating the decode-or-default logic five times.
protocol HasDefault: Codable, Equatable { static var defaultValue: Self { get } }
extension GeneralSettings: HasDefault { public static var defaultValue: Self { .default } }
extension EditorSettings: HasDefault { public static var defaultValue: Self { .default } }
extension MarkdownSettings: HasDefault { public static var defaultValue: Self { .default } }
extension PreviewExportSettings: HasDefault { public static var defaultValue: Self { .default } }
extension FormatSettings: HasDefault { public static var defaultValue: Self { .default } }
```

```swift
// AppSettingsModel.swift
@MainActor
@Observable
public final class AppSettingsModel {
    public var general: GeneralSettings { didSet { store.general = general } }
    public var editor: EditorSettings { didSet { store.editor = editor } }
    public var markdown: MarkdownSettings { didSet { store.markdown = markdown } }
    public var previewExport: PreviewExportSettings { didSet { store.previewExport = previewExport } }
    public var formats: FormatSettings { didSet { store.formats = formats } }

    private var store: any AppSettingsStoring

    public init(store: any AppSettingsStoring = UserDefaultsAppSettingsStore()) {
        self.store = store
        general = store.general
        editor = store.editor
        markdown = store.markdown
        previewExport = store.previewExport
        formats = store.formats
    }
}
```

No manual observer-callback list (unlike `FileTreePreferences`) — every
current consumer of `AppSettingsModel` is a SwiftUI view reached through the
environment (§8), so `@Observable`'s own tracking is sufficient. If a future
epic needs to observe settings from outside SwiftUI's view graph, that
epic adds the callback list then, justified by its own real requirement
(§5's "no seam for a hypothetical future" rule applies to this decision
too).

```swift
// Environment key (App target, not AppSettings — mirrors \.themeController)
private struct AppSettingsKey: EnvironmentKey {
    static let defaultValue: AppSettingsModel? = nil
}
extension EnvironmentValues {
    var appSettings: AppSettingsModel? {
        get { self[AppSettingsKey.self] }
        set { self[AppSettingsKey.self] = newValue }
    }
}
```

---

## 7. State and data flow

```text
┌─────────────────────────┐
│ UserDefaults.standard    │  (or isolated UI-test suite)
│  appSettings.general     │
│  appSettings.editor      │
│  appSettings.markdown    │
│  appSettings.previewExport│
│  appSettings.formats     │
└───────────┬──────────────┘
            │ load-or-default (JSON decode)
            ▼
   UserDefaultsAppSettingsStore
            │
            ▼
      AppSettingsModel            ◀── Settings panes read/write via @Bindable
   (@MainActor @Observable,          (General/Editor/Markdown/Preview&Export/
    one instance, owned by            Formats — General & Preview&Export panes
    AppDelegate)                      also read/write ThemeController and
            │                         FileTreePreferences directly, §5)
            │ read via .environment(\.appSettings, _)
            ▼
┌───────────────────────────────────────────────────────────────┐
│ Consumers (App target, one read site each, recomputed by       │
│ SwiftUI on every relevant body re-evaluation — no push needed) │
│                                                                 │
│  DocumentEditorSplitView.editorConfiguration                   │
│      appSettings.editor → EditorConfiguration +                │
│                            EditingAssistConfiguration           │
│      (format gate — markdown-only assists — still applies       │
│       on top, unchanged from today)                             │
│                                                                 │
│  new-tab preview layout (WindowCoordinator / TabStore.newTab)   │
│      appSettings.previewExport.defaultPreviewLayout →           │
│          PreviewLayoutMode  (replaces the hard-coded            │
│          .defaultMode read for *new* tabs only; an existing     │
│          tab's persisted layout in the session file is          │
│          untouched)                                             │
│                                                                 │
│  ExportPanelView open call site                                │
│      appSettings.previewExport.{defaultExportFormat,style} →    │
│          ExportSelectionModel's initial format/style             │
│                                                                 │
│  AppDelegate.applicationDidFinishLaunching                      │
│      appSettings.general.launchBehavior →                       │
│          scheduleSessionRestore() vs. newDocument()              │
│                                                                 │
│  MarkdownParseSession construction (E06 seam)                   │
│      appSettings.markdown.parsesBlockDirectives →                │
│          MarkdownParseOptions.blockDirectives                    │
│                                                                 │
│  new-document save path (FileStore call site)                   │
│      appSettings.formats.defaultEncodingForNewDocuments →        │
│          encoding parameter, untitled documents only             │
└───────────────────────────────────────────────────────────────┘
```

State transitions are all "last write wins, applied immediately": there is
no pending/staged settings state and no explicit "Apply" action anywhere in
this design (matching the platform convention for a SwiftUI `Settings`
scene, and matching `ThemeController.select`'s immediate-apply behaviour).
A pane control's `didSet`/`onChange` writes straight into `AppSettingsModel`,
which writes straight into `UserDefaults` synchronously.

---

## 8. Concurrency and cancellation

Everything here is `@MainActor`, synchronous, and non-cancellable —
identical in shape to `ThemeController`/`FileTreePreferences`, and for the
same reason: a `UserDefaults` read/write is not expensive enough to justify
moving it off the main actor, and every consumer (SwiftUI views, the launch
decision, the export panel) already runs on the main actor. There is no
`Task`, no `async`, and no cancellation surface introduced by this epic.
`Sendable` conformances on the domain structs exist so `AppSettingsStoring`
itself can be marked `Sendable` (consistent with the sibling protocols),
not because any value crosses an actor boundary in practice.

"What happens when a document changes while work is in flight" (the
concurrency-section prompt in `EPIC_STANDARD.md` §3.8) does not apply here
in the usual sense — there is no in-flight async work — but the adjacent
question, "what happens when settings change while a document is open,"
is answered by §7: the read happens again, synchronously, the next time the
relevant SwiftUI view body evaluates. No document state machine (E01/E18)
is touched by this epic.

---

## 9. Failure model

| Failure | Response |
|---|---|
| No `appSettings.*` key exists yet (fresh install, or a key predating this epic) | `load(_:)` decode fails on a missing key → whole-domain default (J5) |
| A key exists but decodes to a shape the app no longer understands (future field removed/renamed, or hand-edited with `defaults write`) | Whole-domain fallback to default, same code path as above — **not** a partial merge of "whichever fields still decode." Partial merges risk silently reviving a stale field the user meant to reset; whole-domain fallback is simpler and matches `WorkspaceStateStore.sidebarSectionExpanded`'s existing all-or-nothing JSON decode pattern. |
| `EditorSettings.font.familyName` names a font not installed on this Mac (deleted, or a plist edited on another machine) | Resolved at the AppKit boundary (§6's font conversion helper, App target): `NSFont(name:size:)` returning `nil` falls back to `NSFont.monospacedSystemFont(ofSize:weight:.regular)` — the same fallback `EditorConfiguration.default` already uses today. The *stored* preference is left untouched (so if the font reappears — e.g. synced iCloud settings, or the app moves back to the original Mac — it resolves correctly again); only the *resolved* value for this session falls back. |
| `indentationWidth` outside `1...8` (hand-edited defaults, or a future migration bug) | Already clamped by `EditingAssistConfiguration.init`'s existing `min(max(1, indentationWidth), 8)` — this epic adds no new clamping logic, it reuses the guarantee the type already provides. |
| Two windows write different settings values in the same instant | Last write wins, same as `WorkspaceStateStore`'s already-documented behaviour for its own shared suite. `UserDefaults` itself serialises the underlying writes; there is no epic-13-specific race beyond what already exists for every other shared-suite store in this app. |
| `-UITesting` launch with a still-fresh isolated suite | Every domain resolves to its documented default, exactly like J5, because the suite is guaranteed empty (`removePersistentDomain` in `AppDelegate.init`). |
| The O3 detection stub finds no `com.uranusjr.macdown` domain (the common case — most users never had the original MacDown installed) | No behaviour change, no prompt, nothing recorded. Detection failure is not an error. |

There is no failure path that surfaces an error dialog to the user. Every
failure in this table degrades to "use the documented default," which is
the same state a fresh install is already in — this is a deliberate
simplicity choice appropriate to a feature whose entire job is holding
small, low-stakes, individually-recoverable values (contrast with
`RecoveryBuffer`/`FileStore`, where a failure can mean losing an edit and
therefore does surface `lastError`).

---

## 10. Security and trust boundary

Every value this epic introduces is local, typed, user-authored
configuration with no code-execution surface: font family names, booleans,
small closed enums, and one IANA encoding-name string. None of it is
interpreted as a path, a shell command, a URL fetched over the network, or
markup rendered without escaping. `FormatSettings.
defaultEncodingForNewDocuments` is validated against `String.Encoding`'s
known IANA-name table at the read site (§6's helper); an unrecognised value
falls back to UTF-8 rather than being passed through to `FileStore`
unchecked.

The O3 detection stub (§18) reads one thing — whether a `UserDefaults`
persistent domain exists for `com.uranusjr.macdown` — and does not read,
copy, or act on the *contents* of that domain in this epic. There is
nothing here for D9 ("first-party functionality does not upload document
content") to guard against; nothing added by this epic transmits anything
anywhere.

---

## 11. Resource and performance budgets

| Path | Budget | Evidence layer |
|---|---|---|
| `AppSettingsModel` construction (one `UserDefaults` read × 5 domains) at launch | Sub-millisecond; must not be observable against the existing < 1 s cold-launch budget (`MIGRATION_PLAN.md` §8) | Manual observation — five synchronous property-list reads are not worth a dedicated benchmark |
| A single setting write (`didSet` → JSON encode → `UserDefaults.set`) | Sub-millisecond, on the main actor, same class of cost as `ThemeController.select` today | Manual observation |
| Editor font/indentation change re-rendering N open tabs | Must not introduce a visible stall distinguishable from an ordinary SwiftUI re-render; `EditorConfiguration`/`EditingAssistConfiguration` are already `Equatable` and diffed by `EditorTextSystem.apply(_:)`, so only the fields that actually changed cause AppKit-side work | Manual observation across a representative window count (e.g. 8-10 open tabs); no new package benchmark is justified for a change this small relative to `EditorTextSystem`'s existing diffing, which E04 already measured |

Nothing in this epic touches a hot path (keystroke-to-highlight, preview
debounce, folder expansion) — it only changes *inputs* those paths already
accept. No new performance budget row is proposed for
`MIGRATION_PLAN.md` §8.

---

## 12. Accessibility and localisation impact

- Every control uses a native SwiftUI `Form`/`Picker`/`Toggle`/
  `TextField`, which carries VoiceOver labelling and keyboard navigation by
  default; no custom-drawn control is introduced.
- Each pane's tab-bar item gets an explicit `.accessibilityLabel` (matching
  `ExportPanelView`'s existing `.accessibilityLabel("Export format")`
  convention) beyond whatever SF Symbol icon it uses, so a pane is
  identifiable by VoiceOver without relying on the icon.
- All user-facing strings in this epic are plain English `Text("…")`
  literals, consistent with the rest of the app pre-E16 — no ad hoc string
  formatting that would complicate later String Catalog extraction (E16
  performs the actual freeze/translation pass; this epic just avoids
  creating avoidable rework for it, per `EPIC_STANDARD.md` §3.12).
- The font picker must present family names using
  `NSFontManager.shared.availableFontFamilies` so the list matches what
  `NSFont(name:size:)` can actually resolve — this avoids a variant of the
  J4 failure mode (picking a name the resolver then can't use).

---

## 13. Export and interoperability

- Settings values live only in `UserDefaults`; they are never written into
  a document, never round-tripped through open/save, and are unaffected by
  copy/paste, `git`, or export. Reopening a document after a settings
  change simply renders under whatever the *current* settings are — there
  is no per-document settings snapshot to reconcile (unlike, say, a theme
  chosen *for* a document, which does not exist as a concept here either).
- Export interoperability specifically: `PreviewExportSettings` changes
  what the export panel's controls *start* on; it never changes what a
  given, already-configured export actually produces. Two users with
  different `defaultExportFormat` preferences who both explicitly choose
  "PDF" in the panel get byte-identical output for the same document and
  theme — the preference only saves them a click.
- Opening a document when the default encoding preference has changed
  since that document was created has no effect: `defaultEncodingForNewDocuments`
  is read exactly once, at the moment a *new, untitled* document is first
  saved (§4 invariant 2). An already-saved document keeps using its own
  recorded `FileEncodingMetadata`, as it already does today.

---

## 14. Test and evidence matrix

| Requirement | Evidence |
|---|---|
| Every domain struct round-trips through `Codable` | Unit test per domain (`AppSettingsTests`), matching the existing `WorkspaceSessionStoreTests`/`FileEncodingTests` round-trip style |
| Fresh/isolated store returns documented defaults for all five domains (J5) | Unit test constructing `UserDefaultsAppSettingsStore` against an empty, uniquely-named test suite (mirrors `ThemeControllerTests`'/`FileTreePreferencesTests`' existing suite-isolation pattern) |
| A corrupted/mismatched stored value falls back to the whole-domain default, not a partial decode (J4, §9) | Unit test: write malformed `Data` (or a differently-shaped JSON object) under `appSettings.editor`, assert the loaded value equals `EditorSettings.default` |
| `indentationWidth` stays clamped through `AppSettingsModel` | Unit test constructing `EditorSettings(indentationWidth: 0)` and `EditorSettings(indentationWidth: 99)`, asserting both clamp to `1`/`8` |
| Defaults matrix: every key has a default and is read exactly once per launch (issue #14 deliverable #3) | A single test enumerating all five `Key` cases against a fresh suite, asserting each decodes without touching any other key, plus a `AppSettingsModel.init` call-count assertion (constructed once in `AppDelegate`, not re-constructed per pane) |
| Setting a value updates `AppSettingsModel` and is durably persisted (survives a fresh model instance reading the same store) | Unit test: mutate `model.editor`, construct a second `AppSettingsModel` against the same store, assert equality |
| Editor pane change is visible on an already-open tab without relaunch (J1) | App-level/XCUITest: open a document, open Settings, change font, assert the open editor's rendered font changed — this needs real app execution and is recorded per `MIGRATION_PLAN.md` §9's "critical UI execution" rule: **unverified** in this session (no macOS runtime available), a named XCUITest is still written and must actually run on macOS 26 before this epic is considered release-evidence-complete |
| Export panel opens with the preferred default (J3) | Unit test on `ExportSelectionModel`'s App-target construction site + an XCUITest opening the panel and asserting the picker's initial selection — same unverified-in-this-session caveat as above |
| Launch behaviour preference is honoured (session restore vs. new document) | Unit test on the App-target launch-decision helper, isolated from real `NSApplication`/`AppDelegate` lifecycle where possible; full behaviour is otherwise only observable via a real launch, which is release-ledger, not package-test, evidence |
| O3 detection stub correctly reports presence/absence of the legacy domain | Unit test using two isolated `UserDefaults` suites — one seeded to simulate `com.uranusjr.macdown` having a domain, one empty — asserting the detector reports true/false correctly, without touching real `UserDefaults(suiteName: "com.uranusjr.macdown")` |
| SwiftFormat / SwiftLint --strict | CI `lint` job, as for every other PR in this repository |
| `swift build` / `swift test --no-parallel` | CI `build-and-test` job |
| App + CLI build in the required configuration | CI `build-and-test` job (`xcodebuild build`) |

Per `MIGRATION_PLAN.md` §9's environment note, this session has no macOS/
Xcode runtime — every row above that requires real app execution is
recorded as **unverified**, not inferred passed, consistent with how E12
(`epic-12-implementation.md`) and the PR #51 review disclosed the same
limitation. XCUITest *files* are written and must build
(`build-for-testing`), but their actual execution on macOS 26 is a release-
ledger gap this epic inherits rather than closes.

---

## 15. Adversarial corpus

- `appSettings.editor` holding `Data` that is not valid JSON at all
  (truncated/binary garbage) — must fall back cleanly (§9).
- `appSettings.editor` holding *valid* JSON that decodes to an unrelated
  shape (e.g. an array, or an object missing every expected key) — must
  fall back cleanly, not crash `JSONDecoder`.
- `EditorSettings.font.familyName` set to an empty string, an emoji string,
  or a 10,000-character string (defends the font-resolution fallback, §9,
  against anything a `defaults write` or a corrupted iCloud-synced plist
  could contain).
- `FormatSettings.defaultEncodingForNewDocuments` set to a string that is
  not a recognised IANA encoding name (defends the validation named in
  §10).
- `indentationWidth` set to a negative number, `Int.max`, and `0` — all
  three must clamp into `1...8` without trapping.
- Rapid, repeated writes to the same setting in a tight loop (e.g. a
  malfunctioning `Stepper`) — must not corrupt the stored JSON or leave the
  domain in a partially-written state; `UserDefaults.set` is atomic per
  call, so this is mostly a regression guard rather than an expected new
  failure mode.
- Two `AppSettingsModel` instances backed by the *same* real
  `UserDefaults.standard` suite (a scenario that should not occur in
  production — `AppDelegate` constructs exactly one — but is worth a test
  given `ThemeController`/`FileTreePreferences` do not defend against it
  either) writing different values to the same domain in sequence: last
  write wins, and neither instance corrupts the other's unrelated domains.

---

## 16. Expected files and symbols

**New — `AppSettings` target
(`MacDown2/Packages/MacDownKit/Sources/AppSettings/`):**

- `GeneralSettings.swift`
- `FontDescriptor.swift`
- `EditorSettings.swift`
- `MarkdownSettings.swift`
- `PreviewExportSettings.swift`
- `FormatSettings.swift`
- `AppSettingsStoring.swift`
- `UserDefaultsAppSettingsStore.swift`
- `AppSettingsModel.swift`
- `LegacyPreferencesDetector.swift` (§18)
- `AppSettings.swift` — keep the existing module stub or fold its one
  constant into one of the files above; either is fine, this is not an
  architectural decision worth a slice on its own.

**New — tests
(`MacDown2/Packages/MacDownKit/Tests/AppSettingsTests/`):** one test file
per source file above, following this package's existing one-suite-per-type
convention (see `ThemeControllerTests`, `FileTreePreferencesTests` for the
isolated-suite pattern to copy).

**New — App target (`MacDown2/MacDown2/`):**

- `SettingsView.swift` — the `TabView`-based pane container.
- `GeneralSettingsPane.swift`, `EditorSettingsPane.swift`,
  `MarkdownSettingsPane.swift`, `PreviewExportSettingsPane.swift`,
  `FormatSettingsPane.swift`.
- `AppSettingsEnvironment.swift` — the `\.appSettings` environment key
  (§6).

**Modified:**

- `MacDown2/Packages/MacDownKit/Package.swift` — no target-shape change
  needed (both targets already declared); only new source-file discovery,
  which SwiftPM handles automatically.
- `MacDown2/MacDown2/MacDown2App.swift` — add the `Settings { }` scene and
  the `\.appSettings` environment injection.
- `MacDown2/MacDown2/AppDelegate.swift` — construct `appSettings:
  AppSettingsModel`, threaded through the same UI-testing-isolated
  `defaults` as `fileTreePreferences`/`workspaceStateStore`.
- `MacDown2/MacDown2/DocumentEditorSplitView.swift` — `editorConfiguration`
  reads `appSettings.editor` instead of `.default`, still applies the
  existing per-format assist gate on top.
- `MacDown2/MacDown2/ExportPanelView.swift` — `ExportSelectionModel`'s
  construction call site seeds initial `format`/`style` from
  `appSettings.previewExport`.
- The new-tab preview-layout call site (inside `WindowCoordinator+
  Workspace.swift` or `TabStore.newTab`, whichever currently reads
  `PreviewLayoutMode.defaultMode` — confirm exact site during Slice 3, not
  assumed here) — reads `appSettings.previewExport.defaultPreviewLayout`.
- `AppDelegate.applicationDidFinishLaunching` — branches on
  `appSettings.general.launchBehavior` before calling
  `coordinator.scheduleSessionRestore`.
- The `MarkdownParseSession`/`MarkdownParseStore` construction site that
  currently hard-codes `MarkdownParseOptions.default` (exact file to be
  confirmed during Slice 4 — not yet inspected in this pass) — reads
  `appSettings.markdown.parsesBlockDirectives`.
- The brand-new-untitled-document call site (confirmed during Slice 4):
  `FileStore.defaultEncoding` itself is dead in production — every real
  write call site (`FileDocument.saving`/`saveAs`) already passes its own
  `encoding.encoding` explicitly. The actual default lives in
  `FileDocument.init`'s `encoding: FileEncodingMetadata = .utf8Default`
  parameter, reached only via `TabStore.newTab`'s blank-document branch. The
  real chain threaded through instead: `FileDocument.create` and
  `WorkspaceModel.newManagedDocument` both gained an `encoding:` parameter
  (default `.utf8Default`, so every other caller is unaffected), and
  `WindowCoordinator.newDocument(addAsTab:)` — the only production caller of
  `newManagedDocument` — resolves `appSettings.formats` through the new
  `WindowCoordinator.defaultEncoding(from:)` helper
  (`WindowCoordinator+AppSettings.swift`) before calling it.

**Must not change:** `ThemeController`/`ThemePreferenceStore`
(Theme pane presents it, does not modify it), `FileTreePreferences`'
storage shape (General pane presents `opensOnSingleClick`/`filter`, does
not move their storage into `AppSettings`), `WorkspaceStateStore`,
`FileFormatRegistry.defaultFormats`, `FormatManifest.current`,
`ExportRequest`, `ExportComposer`, `BuiltInExportTemplate`,
`MarkdownParseOptions`'s five non-`blockDirectives` fields (left exactly as
documented — still "always on," still not wired — this epic does not
attempt to wire them).

---

## 17. Implementation slices

### Slice 1 — Settings domain types, store, and model (package-only)

- **Goal:** the `AppSettings` target holds real, tested content: the five
  domain structs, `FontDescriptor`, `AppSettingsStoring`,
  `UserDefaultsAppSettingsStore`, `AppSettingsModel`.
- **Dependencies:** none (first slice).
- **Allowed files:** everything listed under "New — `AppSettings` target"
  in §16 except `LegacyPreferencesDetector.swift`, plus its test
  counterparts.
- **Types/behaviours:** exactly as specified in §6; whole-domain
  decode-or-default per §9.
- **Tests/evidence:** the `AppSettingsTests` rows of §14's matrix that do
  not require App-target/XCUITest execution (all of them except the last
  three rows).
- **Verification:** `swift build && swift test --no-parallel` inside
  `MacDown2/Packages/MacDownKit`; `swiftformat --lint` /
  `swiftlint lint --strict` clean.
- **Stop/escalate if:** `Observation`/`@Observable` is unavailable to a
  pure-Foundation-dependency package target for some SwiftPM/toolchain
  reason not anticipated here (unlikely — `FileTreePreferences` already
  proves this works in a leaf module) — escalate rather than adding an
  unplanned dependency to work around it.

### Slice 2 — Settings scene shell + General & Editor panes

- **Goal:** `⌘,` opens a real Settings window with working General and
  Editor panes; `AppSettingsModel` is constructed once in `AppDelegate` and
  reaches both panes and `DocumentEditorSplitView` through the
  environment.
- **Dependencies:** Slice 1.
- **Allowed files:** `MacDown2App.swift`, `AppDelegate.swift`,
  `SettingsView.swift`, `GeneralSettingsPane.swift`,
  `EditorSettingsPane.swift`, `AppSettingsEnvironment.swift`,
  `DocumentEditorSplitView.swift` (the `editorConfiguration` computed
  property only).
- **Types/behaviours:** General pane presents `GeneralSettings.
  launchBehavior` (new) plus `FileTreePreferences.opensOnSingleClick`/
  `.filter` (existing, read/write directly — no new storage). Editor pane
  presents every `EditorSettings` field, with a live font picker
  (`NSFontManager.shared.availableFontFamilies`, §12) and a `Stepper`
  bounded `1...8` for indentation. `AppDelegate.
  applicationDidFinishLaunching` branches on `launchBehavior` before its
  existing session-restore call.
- **Tests/evidence:** J1, J2, and J5 partially verified at the unit level
  (the App-target launch-decision helper, §14); full live-apply and launch-
  behaviour verification remain **unverified** pending real macOS execution
  (§14).
- **Verification:** CI `lint` + `build-and-test` (includes
  `xcodebuild build` for the app scheme); manual dogfood steps for J1/J2/J5
  recorded in the PR description as required-but-not-yet-executed, exactly
  as PR #51's export-pipeline work disclosed the same gap.
- **Stop/escalate if:** `DocumentEditorSplitView`'s existing per-format
  assist gate (`document.format.id == "markdown" ? .markdownDefault :
  .disabled`) turns out to need to change shape to accommodate
  `AppSettings`-sourced values — the architecture in §7 assumes the gate
  stays exactly as it is today, with `AppSettings` only supplying the
  *contents* of the enabled/disabled configurations, not the gating logic
  itself. If that assumption is wrong, stop and escalate rather than
  redesigning the gate inline.

### Slice 3 — Markdown & Preview/Export panes

- **Goal:** the Markdown pane's one real toggle and the Preview & Export
  pane (default layout + default export format/style) work end to end.
- **Dependencies:** Slice 1 (Slice 2 not required, but sequencing after it
  keeps the Settings shell/environment pattern established first).
- **Allowed files:** `MarkdownSettingsPane.swift`,
  `PreviewExportSettingsPane.swift`, `SettingsView.swift` (registering the
  two new tabs), `ExportPanelView.swift` (construction call site only),
  the new-tab preview-layout call site identified during this slice (§16
  flags it as "to be confirmed" — finding and confirming the exact file is
  part of this slice's work, not a pre-existing fact to assume), the
  `MarkdownParseSession`/`MarkdownParseStore` construction call site
  (similarly to be confirmed).
- **Types/behaviours:** exactly §6/§7; no change to `MarkdownParseOptions`
  itself beyond how its `blockDirectives` field is populated at
  construction time.
- **Tests/evidence:** J3 (unit-level seeding + XCUITest, §14); Markdown
  toggle unit-tested by asserting the constructed `MarkdownParseOptions`
  reflects the preference.
- **Verification:** same CI gates as Slice 2.
- **Stop/escalate if:** the actual `MarkdownParseSession`/new-tab-layout
  construction sites turn out to be shared with logic this epic must not
  change (e.g. if preview-layout defaulting is entangled with session
  restore in a way §7 did not anticipate) — stop and report the real call
  site and its coupling before proceeding, rather than reshaping session
  restore to fit.

### Slice 4 — Formats pane + default-encoding wiring

- **Goal:** the Formats pane shows the existing format↔extension table
  read-only and exposes the one new default-encoding preference, wired to
  the actual new-untitled-document save path.
- **Dependencies:** Slice 1.
- **Allowed files:** `FormatSettingsPane.swift`, `SettingsView.swift`
  (registering the tab), the specific `FileStore.defaultEncoding` call
  site for a first-time untitled-document save (to be confirmed during
  this slice — not yet located in this pass).
- **Types/behaviours:** exactly §6/§7; the pane must not present any
  control that could be mistaken for editing `FileFormatRegistry`/
  `FormatManifest` — read-only list, not an editable table.
- **Tests/evidence:** unit test asserting a newly-created untitled
  document's first save uses the preferred encoding when the preference is
  non-default; `FormatRegistryConsistencyTests` must continue to pass
  unmodified (proves this slice did not touch the registry).
- **Verification:** same CI gates as Slice 2.
- **Stop/escalate if:** the "first save of an untitled document" call site
  cannot be cleanly distinguished from "re-save of an existing document"
  without risking D10 (accidentally re-encoding an existing file) — stop
  and report rather than guessing at the distinction.

### Slice 5 — O3 detection stub

- **Goal:** `LegacyPreferencesDetector` exists, is tested, and its result
  is recorded somewhere a human or a future epic can act on (a log line at
  minimum; a `GeneralSettings`-visible read-only status line if a natural
  place exists in the General pane by this point).
- **Dependencies:** Slice 1 (independent of Slices 2-4 otherwise).
- **Allowed files:** `LegacyPreferencesDetector.swift` and its test, plus
  at most one read-only line added to `GeneralSettingsPane.swift` if that
  pane already exists (Slice 2) — this slice does not require Slice 2 to
  be done first; the detector can ship with no UI and be surfaced later.
- **Types/behaviours:** exactly §18.
- **Tests/evidence:** the O3-detection row of §14's matrix.
- **Verification:** same CI gates as Slice 1.
- **Stop/escalate if:** none anticipated — this is the smallest, most
  isolated slice in the epic.

---

## 18. Definition of Done and residual risk

**Done when:**

- [ ] All five Settings panes exist, are reachable via `⌘,`, and each
      control changes behaviour on already-open tabs/windows without
      relaunch (J1-J3).
- [ ] Every domain in §6 round-trips through `Codable`, falls back to its
      documented default on any decode failure (J4), and clamps
      `indentationWidth` correctly.
- [ ] The defaults-matrix test (§14) passes: every key has a default, is
      read once per launch.
- [ ] `FormatRegistryConsistencyTests` and every existing test in
      `ThemeControllerTests`/`FileTreePreferencesTests`/
      `WorkspaceStateStoreTests` (or equivalent) still pass unmodified —
      proof this epic did not disturb the stores it deliberately left
      alone.
- [ ] SwiftFormat, SwiftLint --strict, `swift build`, `swift test
      --no-parallel`, and the app/CLI Release build all pass in CI.
- [ ] `LegacyPreferencesDetector` ships and is tested (§18 below).
- [ ] Issue #14 is updated (or superseded by a linked comment) to record
      the two scope reconciliations from §2.2: the legacy-key migration
      table is not built in this pass (no source available), and O3 ships
      as detection-only.
- [ ] A follow-up GitHub issue is filed for the deferred work in this
      section (legacy key migration, the five inert `MarkdownParseOptions`
      fields, and full O3 import) so it does not silently disappear.

**O3 — old MacDown preferences import, final scope for this epic.**
`LegacyPreferencesDetector` checks, once, whether
`UserDefaults(suiteName: "com.uranusjr.macdown")` has any persistent
domain at all (`UserDefaults(suiteName:).dictionaryRepresentation()`
non-empty). If so, it reports that fact; this epic does nothing further
with it — no key is read, no value is imported, no UI prompts the user.
The real key inventory needed to actually import specific preferences is
no longer unavailable (§2.2 — `MPPreferences.h` was read directly from
`github.com/MacDownApp/macdown`), but building and testing a ~45-key
import/migration map is separate, real work this review round explicitly
chose to defer rather than fold into an already-five-slice epic. This
keeps O3 "resolved" in the sense `EPIC_STANDARD.md` requires (a decision
was made, not silently skipped) while keeping this epic's scope the one
agreed on, not one that grew mid-flight because new information arrived.

**Consciously deferred (residual risk), each to become its own follow-up
issue:**

1. Full old-MacDown preference import (see above) — the source is
   available (`github.com/MacDownApp/macdown`, `MPPreferences.h`/`.m`); the
   work deferred is building the actual key-by-key migration map (several
   legacy keys, e.g. `editorStyleName`/`htmlTemplateName`, name concepts —
   multiple themes, multiple export templates — that don't correspond 1:1
   to MacDown 2's current, deliberately narrower equivalents and need real
   design thought, not just a mechanical copy), plus the handful of small,
   independent preferences the legacy header exposes that this epic's five
   slices don't cover (sync-scroll toggle, editor insets/line-spacing,
   final-newline-on-save, unordered-list marker character, word-count
   display, default export directory — full list in §2.2).
2. The five non-functional `MarkdownParseOptions` fields
   (`tables`/`taskLists`/`strikethrough`/`autolinks`/`footnotes`) remain
   unwired and without UI. Revisit if/when swift-markdown (or a successor
   parse layer) exposes real per-extension control.
3. No macOS dogfooding evidence exists from this session (no macOS
   runtime available) — every "live apply" and "launch behaviour" journey
   (J1, J2, J5, and the launch half of General) is implemented and unit-
   tested at the boundary this session can reach, but not run end-to-end on
   a real Mac. This mirrors the identical, previously-disclosed limitation
   in `epic-12-implementation.md` and PR #51.
4. No new performance budget is proposed (§11) because nothing here sits
   on a measured hot path; if a future audit (E15) finds otherwise, that
   audit owns adding the budget, not this epic pre-emptively.
5. Export template/layout/resource-root/budget/metadata-policy remain
   fixed by design (§1, §4) — not a gap, a deliberate, documented boundary
   this epic does not reopen.
