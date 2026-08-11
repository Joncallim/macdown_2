# EPIC-10 Implementation Architecture — Editing assists

> **Issue:** #11 — `[EPIC-10] Editing assists: list continuation, auto-pairing, indenting`
>
> **Status:** Architecture only. This document is the binding implementation contract for the Epic 10 branch. Production code must be implemented on the same branch only after this plan has been read end-to-end.
>
> **Branch:** `epic/10-editing-assists` → draft PR into `master`.
>
> **Baseline:** branch cut from `master` at `48d852927ac19fd8d2eb0119750c528c3922eae1`, the merged Epic 18 head.
>
> **Depends on:** E04 as built (`EditorView`, `EditorTextSystem`, TextKit 2 and per-window undo), E05 as built (highlighting attached to the existing text system), E07/E08 as built (preview/outline consuming the editor binding), E18 as built (programmatic external-replacement guard and document-safety path).
>
> **No new third-party dependencies. No Package.swift, project.yml, or CI-workflow change is expected.**

---

## 1. Why this epic is next

The data-safety blocker that previously justified doing E18 before E10 is now merged. Epic 10 should therefore make the editor feel like a Markdown editor rather than a generic `NSTextView` without reopening architecture that is already working.

This pass deliberately reconciles the 19 July Epic 10 issue against the live repository. The repository wins where they differ.

Two pieces of the original issue are now stale:

1. **Heading shortcuts `⌘1…6` cannot ship.** The as-built native-tab model uses `⌘1…9` for tab selection in `WorkspaceCommands`. Reclaiming those keys would regress shipped navigation. Epic 10 uses **`⌃⌘1…6` for H1…H6** and **`⌃⌘0` for Paragraph**. `⌘1…9` remains native-tab selection.
2. **Preferences UI does not exist yet.** `AppSettings` is still a stub and E13 owns the Settings scene. Epic 10 therefore introduces a typed assist configuration with documented defaults and a live configuration seam, but **does not build a settings pane**.

The user's current difficulty dogfooding a Debug build also changes the validation policy: correctness still runs through package tests, but perceived typing feel and the `<50 ms` user-facing latency claim must be checked against a **Release app build**, not inferred from Debug-mode behavior.

---

## 2. As-built repository findings that constrain the design

### 2.1 There is already exactly one NSTextView delegate

`EditorView.Coordinator` is the current `NSTextViewDelegate`. It owns:

- `textDidChange` → writes the live `NSTextView.string` into the SwiftUI binding;
- selection callbacks → outline tracking;
- scroll callbacks → preview/outline sync;
- the `isApplyingModelText` echo guard.

**Binding rule:** Epic 10 extends this existing coordinator. Do not install a second delegate, proxy delegate, notification-only parallel editing path, or replacement `NSTextView` owner.

### 2.2 EditorTextSystem is the stable per-document editing object

`EditorTextSystem` owns one live TextKit 2 stack and exposes the existing per-document `UndoManager`. It also has `isPerformingProgrammaticTextUpdate`, introduced for E18, so disk-driven replacements do not flow back as user edits.

**Binding rule:** editing assists are user edits and must continue through the normal `textDidChange` binding path. They must never be classified as E18 programmatic replacements.

### 2.3 Highlighting, preview and outline already consume the ordinary edit path

A successful user edit currently produces:

```text
NSTextView edit
  → EditorView.Coordinator.textDidChange
  → Binding<String>
  → FileDocument value update / dirty state
  → Markdown parse debounce / preview
  → highlighting
  → outline refresh
```

Epic 10 must not add a second publication path to any of those consumers. One assist must look like **one normal NSTextView edit** to the rest of the application.

### 2.4 EditorCore already depends on FileCore, but format gating belongs at the app boundary

The package dependency already exists, so importing FileCore would not create a cycle. Even so, the hot-path assist engine should not repeatedly inspect file metadata. `DocumentEditorSplitView` already knows whether the active document is Markdown.

**Binding rule:** `DocumentEditorSplitView` passes an enabled Markdown assist configuration only for `document.format.id == "markdown"`. Every default/unknown/non-Markdown path is fail-closed (`.disabled`).

This is important because `WindowController` eagerly creates text systems with `EditorConfiguration.default` before SwiftUI mounts the format-specific editor. The default therefore **must have assists disabled** so a JSON/HTML/source file can never receive a transient Markdown assist before the first `updateNSView`.

### 2.5 Native-tab shortcuts already occupy ⌘1…9

`WorkspaceCommands` binds `⌘1…9` to native tab selection, while `⌘⌥1…3` changes editor/preview layout.

**Binding rule:** retain those commands unchanged. Heading commands use `⌃⌘0…6`.

### 2.6 Legacy behavior is available and should be treated as evidence

The original MacDown implementation in `NSTextView+Autocomplete` provides concrete behavior for:

- matching-character completion and type-over;
- wrap-selection;
- paired backspace;
- Tab-to-spaces and Shift-Tab unindent;
- selected-line indent/unindent;
- inline markup toggles;
- list continuation and ordered-list auto-increment;
- blockquote continuation;
- indentation continuation;
- heading conversion;
- smart Home behavior through the text-view command delegate.

Epic 10 ports those semantics where they still make sense and explicitly records dropped behavior rather than silently forgetting it.

---

## 3. Non-negotiable architecture rules

1. **No NSTextView subclass.** Do not add `MacDownTextView`, override `keyDown`, or replace `TextKitStack.textView` with a custom subclass for this epic.
2. **One delegate.** `EditorView.Coordinator` remains the sole `NSTextViewDelegate`.
3. **Use AppKit's text-input pipeline.** Typed replacement interception happens in `textView(_:shouldChangeTextIn:replacementString:)`; command-key behavior happens in `textView(_:doCommandBy:)`.
4. **Pure decision engine, thin AppKit adapter.** Parsing/decision logic is synchronous and deterministic. AppKit mutation is isolated to the text-system/application seam.
5. **One contiguous replacement per assist.** Every text-mutating assist must be representable as one replacement range + one replacement string + one resulting selection. This is how undo stays atomic.
6. **All editor offsets are UTF-16.** Use `NSRange`, `NSString.length`, `NSString.lineRange(for:)`, and UTF-16-aware clamping. Never use `String.count` to calculate editor ranges.
7. **No full Markdown AST on the keystroke path.** E10 operates on the current line / selected line range / immediate neighbors only. Do not call `MarkdownEngine`, wait for a parse, or traverse the document AST to decide an assist.
8. **No Task/actor/debounce in the assist engine.** Keystroke decisions are synchronous. The existing preview/highlight pipelines retain their own asynchronous/debounced behavior.
9. **IME marked text passes through untouched.** Never auto-pair, wrap, or rewrite a replacement while the edit intersects marked text or while the text view is actively composing marked text.
10. **External/model replacements never trigger assists.** Respect both `Coordinator.isApplyingModelText` and `EditorTextSystem.isPerformingProgrammaticTextUpdate`.
11. **Markdown-only means Markdown-only.** In HTML, JSON, YAML, source files and plain text, E10 returns native AppKit behavior for typing, Return, Tab, Backspace and Home.
12. **Do not build E13.** Configuration values exist now; the Settings UI and migration from old MacDown preferences remain E13.
13. **Do not change native tabs, preview, parser, highlighting, external-file monitoring, session schema, file tree, export, or extension architecture.**
14. **No Debug-build performance claims.** Release is the user-feel gate.

---

## 4. Data flow

### 4.1 Typed character / replacement

```text
NSTextInputClient / NSTextView
  → EditorView.Coordinator
       textView(_:shouldChangeTextIn:replacementString:)
  → MarkdownEditingAssistEngine.replacement(...)
       ├── .passthrough → return true; AppKit performs native edit
       ├── .selection  → move selection; return false
       └── .edit       → EditorTextSystem.applyAssistOutcome(...); return false
                           ↓
                         exactly one NSTextView.insertText(...replacementRange:)
                           ↓
                         nested shouldChange callback sees isPerformingEditingAssist
                         and returns true without re-processing
                           ↓
                         textDidChange fires normally exactly once
                           ↓
                         existing Binding/FileDocument/preview/highlight path
```

### 4.2 Return / Tab / Shift-Tab / Backspace / smart Home

```text
NSTextView command
  → EditorView.Coordinator.textView(_:doCommandBy:)
  → command mapped to EditingAssistAction
  → pure engine
       ├── .passthrough → return false; AppKit handles it
       └── handled      → apply outcome; return true
```

The binding must follow Cocoa semantics: `doCommandBy` returns **true when E10 handled the command**, false when AppKit should continue.

### 4.3 Menu / keyboard formatting command

```text
WorkspaceCommands
  → WindowCoordinator.performMarkdownEditingCommand(...)
  → key WindowController
  → active EditorTextSystem
  → EditorTextSystem.performMarkdownCommand(...)
  → same pure engine + same one-replacement applier
  → normal textDidChange binding path
```

Do not synthesize keyboard events to invoke formatting.

---

## 5. Public and internal API contracts

### 5.1 New `EditingAssistConfiguration.swift`

Add:

```swift
public struct EditingAssistConfiguration: Sendable, Equatable {
    public var isEnabled: Bool
    public var continuesBlockPrefixes: Bool
    public var completesMatchingCharacters: Bool
    public var convertsTabsToSpaces: Bool
    public var smartHome: Bool
    public var autoIncrementOrderedLists: Bool
    public var strikethroughEnabled: Bool
    public var indentationWidth: Int

    public init(
        isEnabled: Bool,
        continuesBlockPrefixes: Bool = true,
        completesMatchingCharacters: Bool = true,
        convertsTabsToSpaces: Bool = true,
        smartHome: Bool = true,
        autoIncrementOrderedLists: Bool = true,
        strikethroughEnabled: Bool = true,
        indentationWidth: Int = 4
    )

    public static let disabled: EditingAssistConfiguration
    public static let markdownDefault: EditingAssistConfiguration
}
```

Rules:

- `indentationWidth` is normalized to **1...8** at initialization. Do not allow 0 or a pathological large value into the hot path.
- `.disabled` has `isEnabled == false`; other fields are irrelevant while disabled.
- `.markdownDefault` is enabled, width 4, spaces enabled, prefix continuation enabled, smart Home enabled, ordered-list increment enabled, matching pairs enabled, strikethrough enabled.
- These defaults are the temporary source of truth until E13 exposes settings.

### 5.2 Extend `EditorConfiguration`

Add:

```swift
public var editingAssists: EditingAssistConfiguration
```

and an initializer parameter defaulting to `.disabled`.

`EditorConfiguration.default` must explicitly remain fail-closed with `.disabled`.

`EditorTextSystem.apply(_:)` stores the currently applied assist configuration even when no AppKit appearance property changes. Add:

```swift
public private(set) var editingAssistConfiguration: EditingAssistConfiguration = .disabled
```

The coordinator and menu-command path read this value. Do not duplicate assist configuration in the SwiftUI coordinator.

### 5.3 New `EditingAssistOutcome.swift`

Internal package types:

```swift
struct EditingAssistEdit: Equatable {
    let replacementRange: NSRange
    let replacementString: String
    let resultingSelection: NSRange
    let undoActionName: String
}

enum EditingAssistOutcome: Equatable {
    case passthrough
    case edit(EditingAssistEdit)
    case selection(NSRange)
    case handledNoChange
}
```

`handledNoChange` is allowed only for a command E10 intentionally consumes without a text mutation. Do not use it to hide an unimplemented branch.

### 5.4 New `MarkdownEditingCommand.swift`

Public because the app command layer needs it:

```swift
public enum MarkdownEditingCommand: Sendable, Equatable {
    case bold
    case italic
    case inlineCode
    case heading(level: Int)   // 1...6 only
    case paragraph
}
```

`heading(level:)` rejects values outside 1...6 at the `EditorTextSystem` boundary (return false / assertion in Debug); the pure engine is never passed an invalid level.

### 5.5 New internal action type

```swift
enum EditingAssistAction: Equatable {
    case replacement(range: NSRange, string: String, hasMarkedText: Bool, markedRange: NSRange)
    case insertNewline
    case insertTab
    case insertBacktab
    case deleteBackward
    case smartHome
    case markdownCommand(MarkdownEditingCommand)
}
```

The engine always also receives:

- current `String`;
- current `NSRange` selection;
- current `EditingAssistConfiguration`.

### 5.6 New `MarkdownEditingAssistEngine.swift`

Internal, stateless, synchronous:

```swift
struct MarkdownEditingAssistEngine {
    static func outcome(
        for action: EditingAssistAction,
        text: String,
        selection: NSRange,
        configuration: EditingAssistConfiguration
    ) -> EditingAssistOutcome
}
```

The first branch is always:

```swift
guard configuration.isEnabled else { return .passthrough }
```

Internally bridge `text` to `NSString` once per call and perform all range arithmetic in UTF-16.

### 5.7 Extend `EditorTextSystem`

Add an internal re-entrancy state distinct from E18's programmatic-update state:

```swift
private(set) var isPerformingEditingAssist = false
```

Add internal application:

```swift
@discardableResult
func applyAssistOutcome(_ outcome: EditingAssistOutcome) -> Bool
```

and public menu-command entry:

```swift
@discardableResult
public func performMarkdownCommand(_ command: MarkdownEditingCommand) -> Bool
```

`applyAssistOutcome` behavior:

- `.passthrough` → `false`.
- `.selection(range)` → clamp to live UTF-16 text, set selection, return `true`; no undo item.
- `.handledNoChange` → return `true`.
- `.edit(edit)`:
  1. set `isPerformingEditingAssist = true` with `defer` reset;
  2. call **exactly one** `textView.insertText(edit.replacementString, replacementRange: edit.replacementRange)`;
  3. set the clamped resulting selection;
  4. give the undo manager `edit.undoActionName` where AppKit has created an undo action;
  5. return `true`.

Do not mutate `NSTextStorage` directly. Do not manually call `textDidChange`. Let `NSTextView.insertText` drive the same AppKit/delegate path as ordinary input.

The coordinator's nested `shouldChangeTextIn` invocation sees `isPerformingEditingAssist == true` and immediately returns `true`, preventing recursive transformation while still allowing the inner AppKit edit.

---

## 6. EditorView coordinator wiring

### 6.1 Replacement hook

Implement the existing delegate method:

```swift
public func textView(
    _ textView: NSTextView,
    shouldChangeTextIn affectedCharRange: NSRange,
    replacementString: String?
) -> Bool
```

Required guard order:

1. `system` exists.
2. `replacementString` is non-nil; otherwise native behavior.
3. `!isApplyingModelText`.
4. `!system.isPerformingProgrammaticTextUpdate`.
5. `!system.isPerformingEditingAssist`.
6. current assist configuration is enabled.
7. if `textView.hasMarkedText` **or** `NSIntersectionRange(textView.markedRange, affectedCharRange).length > 0`, return true without invoking the engine.

Then ask the pure engine for `.replacement(...)`. If the outcome is handled, apply it and return `false`; otherwise return `true`.

Do not perform list/Return behavior here. Return is command-selector behavior.

### 6.2 Command hook

Implement:

```swift
public func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool
```

Map only these AppKit commands:

- `insertNewline:` → `.insertNewline`
- `insertTab:` → `.insertTab`
- `insertBacktab:` → `.insertBacktab`
- `deleteBackward:` → `.deleteBackward`
- `moveToLeftEndOfLine:` → `.smartHome`

Everything else returns false immediately.

This mirrors the original MacDown delegation seam and avoids intercepting raw key codes, dead keys, accessibility input, or input-method composition.

For smart Home specifically, `moveToLeftEndOfLine:` is the canonical behavior inherited from MacDown 1. The local manual gate must verify that the physical/key-binding path used on macOS 26 reaches this selector. If macOS 26 emits a different *documented NSText command selector* for the plain Home binding, add that observed selector to the same `.smartHome` action; do not add a `keyDown` override.

---

## 7. Behavior specification — Return / continuation

The continuation parser is line-local. It must not regex or scan the complete document.

Create an internal `MarkdownLinePrefix` value in `MarkdownEditingAssistEngine.swift` or a separate `MarkdownLinePrefix.swift` if lint length requires it:

```swift
struct MarkdownLinePrefix: Equatable {
    let indentation: String
    let blockquotePrefix: String
    let listMarker: ListMarker?
    let taskMarker: TaskMarker?
    let contentRangeInLine: NSRange
}
```

`ListMarker` is internal:

```swift
enum ListMarker: Equatable {
    case unordered(Character)     // -, +, *
    case ordered(number: Int)     // `N.` only for E10
}
```

`TaskMarker` recognizes `[ ]`, `[x]`, `[X]`. A continued task always emits `[ ]`.

### 7.1 Prefix grammar

Parse only from line start to the caret:

```text
[indentation]
[zero or more blockquote markers, preserving exact `>` + optional space spelling]
[optional list marker + following whitespace]
[optional task marker + following whitespace]
[content before caret]
```

Support composition, not only isolated constructs. Examples:

- `- item` → `- ` continuation.
- `  4. item` → `  5. `.
- `> quote` → `> `.
- `> - item` → `> - `.
- `> - [x] done` → `> - [ ] `.
- `    indented` → preserve four leading spaces on the new line.

This deliberately improves an old MacDown seam: MacDown 1 tested list continuation before blockquote continuation, so a combined `> - item` did not preserve the full composition. E10 treats the combined prefix as one Markdown construct.

### 7.2 Normal continuation

The assist only runs when the selection length is zero.

For non-empty content before the caret:

- unordered list → insert `\n` + indentation + blockquote prefix + the same marker + one space;
- ordered list → same but increment the integer when `autoIncrementOrderedLists`; otherwise repeat it;
- task list → same list prefix + `[ ] ` regardless of prior checked state;
- blockquote-only → `\n` + indentation + exact blockquote prefix;
- indentation-only with at least one non-whitespace content character → `\n` + indentation;
- no recognized prefix → `.passthrough` so AppKit inserts a normal newline.

When Return splits a line in the middle, the prefix is inserted before the tail exactly once; text after the caret remains untouched.

### 7.3 Empty construct termination

An "empty item" means the recognized construct prefix exists and the content after that prefix up to the caret is whitespace-only.

- empty list/task item → exit the list level while preserving outer indentation and any blockquote prefix;
- empty blockquote-only line → remove the blockquote prefix and insert a plain newline at the same indentation;
- empty combined blockquote + list → exit the list but remain in the outer blockquote;
- plain whitespace-only line with no block/list construct → native newline.

The whole operation must be one contiguous replacement transaction, not "delete marker" followed by "insert newline" as two undoable edits.

### 7.4 Existing-next-prefix suppression

MacDown 1 contained logic intended to avoid duplicating an already-present matching marker after Return. Preserve the useful behavior, but implement it deterministically from the original text rather than mutating first and inspecting a stale snapshot:

- if the tail at the insertion point already begins with the exact continuation prefix because Return is splitting immediately before it, insert only the newline/indent needed to expose that prefix;
- never duplicate the prefix.

Add a direct regression test; do not copy the old mutation-first implementation literally.

### 7.5 CRLF

Line discovery must use `NSString` line-range APIs and preserve the document's existing line separator at the active line when it is determinable. If the current separator cannot be observed (e.g. last line), use `\n`, matching NSTextView's normal insertion behavior. Do not accidentally leave a `\r` inside the parsed prefix.

---

## 8. Behavior specification — matching characters and selection wrapping

### 8.1 Structural pair table

Port the legacy matching table as data, not a switch spread across delegate code:

- `(` → `)`
- `[` → `]`
- `{` → `}`
- `<` → `>`
- `'` → `'`
- `"` → `"`
- full-width parentheses `（` → `）`
- corner brackets `「` → `」`
- white corner brackets `『` → `』`
- left/right curly single quotes
- left/right curly double quotes
- single/double guillemets
- East Asian single/double angle brackets

Keep the table inside the pure engine.

### 8.2 No-selection opener completion

Port MacDown 1's conservative boundary rule:

- replacement must be one UTF-16 unit / one supported opener;
- the following character is end-of-document or whitespace/newline/punctuation;
- for symmetric pairs (`'`, `"`), the previous character is also a boundary/end;
- asymmetric brackets may pair after a non-boundary previous character, matching legacy behavior.

Outcome: one edit inserts opener + closer at the affected range and returns a selection between them.

Do **not** auto-close `*`, `_`, backtick, `~`, or `=` on an empty selection. Legacy MacDown only auto-completed structural matching characters in this path; Markdown markup characters participated in **selection wrapping**. This is intentional: automatically emitting `**` while the user is typing ordinary emphasis is materially more intrusive than the behavior this epic is supposed to port.

### 8.3 Type-over closer

If the typed character is a supported structural closer and the next live character is already that closer, return `.selection` one UTF-16 unit to the right and suppress the insertion.

No undo item is created because the text did not change.

### 8.4 Selection wrapping

When the affected range has non-zero length and the replacement is one supported opener/markup character:

- structural opener wraps selected text with its mapped closer;
- `*`, `_`, and backtick wrap with the same character;
- `~` wraps only when `strikethroughEnabled`;
- `=` selection wrapping from old MacDown is **not ported** in E10 because the current Markdown product contract does not expose the old highlight/underline extension that behavior belonged to. It is recorded as deliberately dropped, not forgotten.

The selected logical content remains selected inside the newly inserted delimiters.

### 8.5 Paired Backspace

Port `deleteMatchingCharactersAround` for structural pairs only:

- collapsed caret between an adjacent recognized opener+closer;
- Backspace removes both characters in one edit and leaves the caret at the pair's start.

Do not invent paired deletion for Markdown markup delimiters in E10.

### 8.6 IME safety

Unlike old MacDown's partial ASCII/non-ASCII special case, E10 is fail-open for the whole marked-text composition interval: no E10 transformation while `hasMarkedText` is true or the affected range intersects `markedRange`.

This is an intentional safety deviation from legacy behavior and must be listed in the parity table. The final committed text is still a normal user edit; it simply does not retroactively gain a pair after composition ends.

---

## 9. Behavior specification — Tab / Shift-Tab indentation

All indentation is UTF-16 selection aware but indentation width is ASCII-space based.

### 9.1 Collapsed selection + Tab

When `convertsTabsToSpaces` is true:

- determine the UTF-16 column from line start to caret;
- insert `indentationWidth - (column % indentationWidth)` spaces;
- if modulo is zero, insert a full `indentationWidth` spaces.

This ports `insertSpacesForTab`, generalized from hardcoded width 4.

When conversion is disabled, `.passthrough` and AppKit inserts its native tab.

### 9.2 Non-empty selection + Tab

Replace the full selected logical line range once:

- prefix each selected non-terminal line with exactly `indentationWidth` spaces;
- do not create padding on the synthetic empty line produced solely because a selection ends immediately after a trailing newline;
- adjust selection so the same logical text remains selected after the per-line shifts.

One replacement = one undo.

### 9.3 Non-empty selection + Shift-Tab

For each selected line remove, in order:

1. one leading tab, or
2. up to `indentationWidth` leading spaces.

Replace the entire selected line range once and remap the selection by the exact removed UTF-16 counts.

### 9.4 Collapsed selection + Shift-Tab

Remove spaces immediately before the caret back to the previous indentation stop, capped at `indentationWidth`. If there is one leading tab immediately before the caret within indentation, remove the tab.

If there is nothing valid to unindent, return `.passthrough` to preserve native responder traversal semantics rather than swallowing Shift-Tab globally.

---

## 10. Behavior specification — smart Home

Smart Home is enabled only for Markdown assist configuration.

For a collapsed selection on the current line:

1. calculate line start;
2. calculate first non-whitespace UTF-16 location on that line;
3. if caret is not at first non-whitespace, move there;
4. if caret is already at first non-whitespace, move to physical line start;
5. on an all-whitespace line, line start is the only target.

For a non-empty selection, collapse to the computed target; do not preserve an extending selection in E10.

Use the AppKit `moveToLeftEndOfLine:` command seam matching MacDown 1. Do not intercept raw Home key codes.

---

## 11. Behavior specification — markup commands

### 11.1 Inline toggles

Mappings:

- `.bold` → prefix/suffix `**`
- `.italic` → `*`
- `.inlineCode` → backtick

For all three:

- if the current selection is already surrounded by the exact prefix/suffix, remove them and retain the logical selection;
- otherwise wrap the selection and retain the logical selection;
- empty selection is valid: inserting delimiters leaves the caret between them.

Port MacDown's emphasis ambiguity rule:

- a selection inside `***selection***` counts as surrounded by single `*`;
- a selection inside only `**selection**` does **not** count as single-`*` italic markup.

All toggle operations are one contiguous replacement.

### 11.2 Heading / paragraph conversion

`.heading(level: 1...6)` and `.paragraph` operate on every logical line touched by the current selection.

For each processed non-empty line:

1. remove one existing leading ATX heading prefix matching `#{1,6}` followed by at least one space/tab;
2. for heading, prepend exactly `level` `#` characters + one space;
3. for paragraph, prepend nothing.

Rules:

- preserve all content after the removed prefix verbatim;
- whitespace-only lines inside a multi-line selection are not converted;
- when the only selected line is blank, a heading command may insert the heading prefix so the user can type the heading immediately, matching the useful legacy behavior;
- do not convert Setext underline syntax in E10;
- replace the complete affected line range exactly once;
- remap selection using per-line UTF-16 deltas so the same logical content remains selected.

### 11.3 Command shortcuts

Add one top-level `CommandMenu("Markup")` (or, if implementation confirms a clean existing Format-group insertion without duplicating system menus, a `Markdown` submenu in Format; do not create two competing menu copies).

Binding shortcuts:

- Bold — `⌘B`
- Italic — `⌘I`
- Inline Code — `⌘E`
- Paragraph — `⌃⌘0`
- Heading 1…6 — `⌃⌘1…6`

Do not change:

- native tab `⌘1…9`;
- layout `⌘⌥1…3`;
- sidebar/outline shortcuts.

### 11.4 WindowCoordinator command bridge

Put the bridge in a new app-target extension file to avoid further growing `WindowCoordinator.swift`:

`MacDown2/MacDown2/WindowCoordinator+Editing.swift`

Add:

```swift
var canPerformMarkdownEditingCommand: Bool { get }

@discardableResult
func performMarkdownEditingCommand(_ command: MarkdownEditingCommand) -> Bool
```

Resolve the key `WindowController`, active tab identity and existing text system. Guard all of:

- key document exists;
- `document.format.id == "markdown"`;
- text system exists;
- the text view is the key window's current first responder when the command is invoked.

Do not apply a formatting command to a stale selection in a background/native sibling tab or while the sidebar owns keyboard focus.

`WorkspaceCommands` repeats the format guard in `.disabled(...)` and the bridge repeats it before mutation (UI enablement is not a safety boundary).

---

## 12. App format wiring

Modify only `DocumentEditorSplitView.editorConfiguration`:

```swift
private var editorConfiguration: EditorConfiguration {
    var config = EditorConfiguration.default
    config.scrollsPastEnd = false
    config.editingAssists = document.format.id == "markdown" ? .markdownDefault : .disabled
    return config
}
```

Use the format id, not the preview capability (`HTML` is also `.rendered`).

On Save As from Markdown to another extension, the ordinary view/configuration update disables assists on the existing text system. On Save As into Markdown, it enables them. Add an integration test at the highest practical seam for this state change.

No `AppSettings` changes land in this epic.

---

## 13. Legacy parity ledger

The acceptance criterion says every behavior in `NSTextView+Autocomplete` is ported or explicitly dropped. The implementation record must contain this table, updated to actual shipped status:

| Legacy API | E10 disposition |
|---|---|
| `substringInRange:isSurroundedByPrefix:suffix:` | Port as internal inline-markup helper, including `*` vs `**`/`***` rule |
| `insertSpacesForTab` | Port, generalized to configured 1...8 width |
| `completeMatchingCharactersForTextInRange` | Port through replacement engine |
| `completeMatchingCharacterForText:atLocation:` | Port structural opener/type-over semantics |
| `wrapTextInRange` | Port as generic one-replacement wrapper helper |
| `wrapMatchingCharactersOfCharacter` | Port structural + `*`/`_`/backtick + strikethrough selection wrapping; drop `=` |
| `deleteMatchingCharactersAround` | Port structural paired Backspace |
| `unindentForSpacesBefore` | Port, generalized width |
| `toggleForMarkupPrefix:suffix:` | Port for bold/italic/code |
| `toggleBlockWithPattern:prefix:` | **Deliberately deferred** — generic quote/list block-toggle commands are not in issue #11; continuation remains in scope |
| `indentSelectedLinesWithPadding` | Port |
| `unindentSelectedLines` | Port |
| `insertMappedContent` | **Drop** — legacy bundled data-map helper is not an editor feature/product requirement |
| `completeNextListItem` | Port and extend with task lists/composed quote+list prefixes |
| `completeNextBlockquoteLine` | Port and integrate with unified prefix parser |
| `completeNextIndentedLine` | Port |
| `makeHeaderForSelectedLinesWithLevel` | Port as H1…H6 + Paragraph commands |
| old partial marked-text matching | **Replace deliberately** with full marked-text pass-through for IME safety |

Do not close #11 until this ledger reflects implementation reality and any additional deviations discovered during review.

---

## 14. Exact file layout

Expected new files:

```text
MacDown2/Packages/MacDownKit/Sources/EditorCore/
  EditingAssistConfiguration.swift
  EditingAssistOutcome.swift
  MarkdownEditingCommand.swift
  MarkdownEditingAssistEngine.swift
  EditorTextSystem+EditingAssists.swift

MacDown2/Packages/MacDownKit/Tests/EditorCoreTests/
  EditingAssistReplacementTests.swift
  EditingAssistNewlineTests.swift
  EditingAssistIndentationTests.swift
  EditingAssistFormattingTests.swift
  EditingAssistSmartHomeTests.swift
  EditingAssistIntegrationTests.swift
  EditingAssistPerformanceTests.swift

MacDown2/MacDown2/
  WindowCoordinator+Editing.swift

MacDown2/MacDown2UITests/
  EditingAssistsUITests.swift
```

Expected modified files:

```text
MacDown2/Packages/MacDownKit/Sources/EditorCore/EditorConfiguration.swift
MacDown2/Packages/MacDownKit/Sources/EditorCore/EditorTextSystem.swift
MacDown2/Packages/MacDownKit/Sources/EditorCore/EditorView.swift
MacDown2/MacDown2/DocumentEditorSplitView.swift
MacDown2/MacDown2/WorkspaceCommands.swift
planning/epic-10-implementation.md              # implementation record appended as work lands
planning/epics/EPIC-10-editing-assists.md       # mark implemented only after gates pass
README.md                                       # status only after implementation is real
```

Files that should **not** change without an explicit architecture-review comment first:

```text
MacDown2/Packages/MacDownKit/Package.swift
MacDown2/project.yml
.github/workflows/ci.yml
MarkdownEngine/**
Highlighting/**
Preview/**
FileTree/**
External-file monitor/controller architecture
Workspace session schema
```

---

## 15. Unit and integration test matrix

Tests should be table-driven where behavior differs only by marker/delimiter. Do not create hundreds of near-identical handwritten functions.

### 15.1 Replacement / pairs

At minimum:

- each structural opener pairs at a valid boundary;
- structural opener before ordinary alphanumeric following text does not pair;
- symmetric quotes require a previous boundary;
- closer typed before identical closer moves selection instead of duplicating;
- selection wraps for each structural opener;
- selection wraps with `*`, `_`, backtick;
- selection wraps with `~` only when strikethrough enabled;
- `=` is not transformed;
- markup character with collapsed selection is native/pass-through;
- paired Backspace deletes both structural characters once;
- ordinary Backspace passes through;
- marked-text / intersecting-marked-range replacements pass through;
- emoji/CJK text around the pair proves UTF-16 range arithmetic is correct.

### 15.2 Newline / continuation

At minimum:

- `-`, `+`, `*` unordered markers continue unchanged;
- ordered `1.` increments to `2.`;
- multi-digit ordered values increment correctly;
- auto-increment disabled repeats the number;
- `[ ]`, `[x]`, `[X]` tasks continue as `[ ]`;
- blockquote marker spelling/spacing is preserved;
- nested blockquotes preserve the full prefix;
- `> - item` continues `> - `;
- `> - [x] item` continues `> - [ ] `;
- indentation-only line preserves indent;
- plain line returns passthrough;
- empty unordered/ordered/task item exits the list;
- empty list nested inside blockquote exits list but retains quote;
- empty blockquote exits quote;
- selection present returns passthrough;
- Return in the middle of content retains the tail after the continuation prefix;
- already-present exact continuation prefix is not duplicated;
- CRLF fixture does not leak `\r` into the prefix.

### 15.3 Indentation

At minimum:

- width 4 at columns 0,1,2,3,4 inserts 4,3,2,1,4 spaces;
- non-default widths 2 and 8;
- selected one-line and multi-line indent;
- selection ending exactly at newline does not indent a synthetic extra line;
- selected lines unindent one leading tab;
- selected lines unindent up to configured spaces;
- collapsed Shift-Tab removes to previous stop;
- collapsed Shift-Tab with no removable indent passes through;
- UTF-16 selection spanning emoji/CJK remaps correctly.

### 15.4 Smart Home

At minimum:

- indented content: first trigger → first non-whitespace;
- second trigger from first non-whitespace → column zero;
- no indentation → column zero;
- all-whitespace line → column zero;
- line after emoji/CJK in prior lines calculates the current UTF-16 line start correctly.

### 15.5 Formatting

At minimum:

- bold wraps/toggles off;
- italic wraps/toggles off;
- italic does not strip only-strong `**` delimiters;
- italic correctly recognizes the outer single stars in `***...***`;
- inline code wraps/toggles off;
- empty selection leaves caret inside delimiters;
- H1…H6 replaces existing ATX level rather than stacking prefixes;
- Paragraph strips ATX prefix;
- multi-line heading command skips blank interior lines;
- selection remains on same logical content after positive/negative per-line shifts;
- CRLF selection remains structurally valid.

### 15.6 Disabled / non-Markdown behavior

This is a release blocker, not a token test:

- `.disabled` returns `.passthrough` for every action family;
- `EditorConfiguration.default.editingAssists == .disabled`;
- `DocumentEditorSplitView` selects `.markdownDefault` only for format id `markdown`;
- a text-system config transition enabled → disabled stops the very next assist;
- a disabled pair opener does not inject a closer;
- disabled Return does not inject a Markdown prefix.

### 15.7 One edit / one binding publication

Add a coordinator/text-system integration test with a real `NSTextView` and binding counter:

- trigger one pair assist → binding setter called once with final text;
- trigger one list continuation → once;
- trigger one formatting command → once.

Do not accept an implementation where the intermediate deletion/insertion states escape into FileDocument/preview.

### 15.8 Undo / redo

Use a mounted AppKit text system where necessary so native undo registration is active. Parameterize representative mutation classes:

- structural pair insertion;
- list continuation;
- selected-lines indentation;
- bold toggle;
- heading conversion.

For each:

1. capture exact original text + selection;
2. perform assist;
3. **one Undo** restores original text (and selection where AppKit provides it);
4. **one Redo** restores transformed text;
5. there is no intermediate half-applied state on the undo stack.

Type-over closer and smart Home are selection-only and should not add text undo entries.

### 15.9 Programmatic-update regression

Exercise both existing non-user paths:

- `updateNSView` model push guarded by `isApplyingModelText`;
- E18 `replaceTextFromExternal(...clearUndo:)` guarded by `isPerformingProgrammaticTextUpdate`.

Neither path may invoke an E10 transformation even if replacement text contains an opener/marker.

---

## 16. Performance gates

The current EditorCore already has a `<50 ms` 1 MB keystroke test. E10 must not weaken or delete it.

Add two focused measurements:

1. **No-op assist decision, 1 MB document:** ordinary alphanumeric replacement through the engine near a representative line must be line-local and complete with substantial headroom. Record the measured value; target **<5 ms Release** on the development Mac, but do not encode an unrealistically tight cross-runner wall-clock threshold if CI variance proves it flaky.
2. **Handled assist + viewport layout, 1 MB:** representative pair or newline continuation through the actual EditorTextSystem adapter must remain inside the existing **<50 ms** user-facing keystroke budget in Release.

Structural requirement is stronger than a microbenchmark: code review must be able to see that the common path does **not** scan from document start to caret or run a whole-document regex/AST parse.

### Debug vs Release

- `swift test` remains the correctness gate.
- Run `swift test -c release` for the E10 performance evidence.
- Do not claim that Debug app typing speed represents product performance.

---

## 17. XCUITest / manual behavior gate

### 17.1 XCUITest

Add `EditingAssistsUITests.swift` using the existing `-UITesting`/open-file hooks. Minimum smoke:

1. open a Markdown document;
2. focus editor;
3. type `- item` + Return;
4. assert the editor now contains the continued `- ` prefix;
5. type another character to prove normal input continues after the assist.

If stable with the existing accessibility seam, add one non-Markdown smoke that types `(` into `.txt` and verifies no synthetic `)`.

CI reality remains as documented by E04: the target is compiled by `build-for-testing`; actual XCUITest execution requires a compatible macOS 26 environment. Do not mark a UI behavior verified merely because the bundle compiled.

### 17.2 Release dogfood build

Because Debug mode is not a useful feel/performance gate, use a deterministic Release build for the human pass:

```bash
rm -rf /tmp/MacDown2-E10
cd MacDown2
xcodegen generate
xcodebuild \
  -project MacDown2.xcodeproj \
  -scheme MacDown2 \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/MacDown2-E10 \
  build
open /tmp/MacDown2-E10/Build/Products/Release/MacDown2.app
```

Manual matrix:

- type prose normally for several minutes — no synthetic characters or lag;
- unordered/ordered/task lists, including termination;
- nested blockquote + list;
- pair open/type-over/backspace;
- selection wrapping;
- Tab/Shift-Tab single and multi-line;
- smart Home;
- Bold/Italic/Code and H1…H6/Paragraph menu shortcuts;
- Undo once for each mutation class;
- switch a `.md` file to `.txt` via Save As and confirm Markdown assists stop;
- switch back to Markdown and confirm they resume;
- exercise at least one IME composition path and confirm E10 leaves marked text alone;
- preview/highlighting/outline remain responsive after each assisted edit.

Record concrete failures on the PR; fix them in focused commits. Do not broaden E10 because dogfooding suggests unrelated product features.

---

## 18. Ordered implementation commits

Implementation agents must follow this order. Commits 1–4 are serial because each consumes the contract established by the prior commit.

### Commit 1 — pure assist engine + exhaustive pure tests

Only:

- `EditingAssistConfiguration.swift`
- `EditingAssistOutcome.swift`
- `MarkdownEditingCommand.swift`
- `MarkdownEditingAssistEngine.swift`
- pure `EditingAssist*Tests.swift`

No EditorView, app-target, WorkspaceCommands, Package.swift or UI-test changes.

Exit gate: package compiles; pure tests cover continuation, pairing, indentation, smart Home and formatting including UTF-16 cases.

### Commit 2 — configuration + format gate

Only:

- `EditorConfiguration.swift`
- `EditorTextSystem.swift` configuration readout
- `DocumentEditorSplitView.swift`
- configuration/non-Markdown tests

Exit gate: `.default` is disabled, Markdown config enables, non-Markdown disables, live config transitions are tested.

### Commit 3 — delegate interception + one-edit adapter

Only:

- `EditorView.swift`
- `EditorTextSystem+EditingAssists.swift`
- coordinator/system integration tests
- undo/reentrancy/programmatic-update tests

Exit gate: one assist → one AppKit edit → one binding publication; Undo is atomic; ordinary input and E18 replacement behavior remain unchanged.

### Commit 4 — app markup commands and shortcut reconciliation

Only:

- `WindowCoordinator+Editing.swift`
- `WorkspaceCommands.swift`
- formatting command integration tests where possible

Exit gate: `⌘B`, `⌘I`, `⌘E`, `⌃⌘0…6` work on the key Markdown editor; `⌘1…9` native tabs and `⌘⌥1…3` layout are unchanged.

### Commit 5 — performance + UI test + implementation record

- performance tests/evidence;
- `EditingAssistsUITests.swift`;
- Release dogfood findings/fixes that are strictly E10;
- update this document with actual implementation notes/deviations;
- update Epic 10 spec/README status only when the feature is actually complete.

Do not squash away the architecture/implementation/review boundaries while the PR is under review.

---

## 19. Validation gate before marking PR ready

Run and record all applicable results:

```bash
# Debug package correctness
cd MacDown2/Packages/MacDownKit
swift build
swift test

# Release package + performance evidence
swift build -c release
swift test -c release

# Thread sanitizer for delegate/re-entrancy regressions
swift test --sanitize=thread

# App/CLI/UI-test build
cd ../..
xcodegen generate
xcodebuild -project MacDown2.xcodeproj -scheme MacDown2 -destination 'platform=macOS' build
xcodebuild -project MacDown2.xcodeproj -scheme macdown2 -destination 'platform=macOS' build
xcodebuild -project MacDown2.xcodeproj -scheme MacDown2 -destination 'platform=macOS' build-for-testing

# Style / patch hygiene
swiftformat --lint MacDown2
swiftlint lint --strict MacDown2
git diff --check master...HEAD
```

Then perform the §17.2 Release dogfood matrix.

Do not mark ready if:

- package tests are green but Release dogfooding exposes typing interference;
- a non-Markdown file receives an E10 assist;
- one assisted action takes two Undos;
- marked text is corrupted;
- an assist creates multiple binding publications;
- the existing `<50 ms` keystroke budget regresses;
- native-tab shortcuts are displaced;
- any E18 external-replacement regression appears.

---

## 20. Review checklist — orthogonal pass

The reviewer must explicitly audit these independent dimensions rather than only re-running tests:

### Correctness

- UTF-16 arithmetic at every range boundary;
- lineRange behavior at document start/end and trailing newline;
- ordered-list overflow/invalid integer handling fails to repeat safely rather than trapping;
- selection remap for multi-line prefix changes;
- empty construct termination;
- nested quote/list/task composition.

### AppKit semantics

- delegate return values are correct (`true` handled in `doCommandBy`, `false` when native should continue);
- nested assist insertion does not recursively re-assist;
- `textDidChange` is neither duplicated nor suppressed;
- should-change validation is not bypassed by direct text-storage mutation;
- undo grouping is native/atomic.

### Safety / integration

- IME marked text bypass;
- model/external replacements bypass;
- Markdown-only fail-closed default;
- Save As format transition;
- highlight/preview/outline receive one final value;
- no new retain cycle between coordinator and text system.

### Performance

- common no-op input is constant/local with respect to document size apart from unavoidable NSTextView string access;
- no full-document regex, `components(separatedBy:)`, AST parse or per-keystroke Task;
- selection-line operations scale with selected lines, not full document;
- performance results are from Release when making user-facing claims.

### Scope

Reject changes that opportunistically add:

- autocomplete/snippet/link/image insertion;
- generic command palette work;
- E13 settings UI;
- parser/highlighter rewrites;
- native-tab changes;
- extension/plugin changes.

---

## 21. Lower-tier implementation handoff

An implementation agent should not make product or architecture decisions beyond this list.

### Start here

1. Branch is already `epic/10-editing-assists` from `48d8529`.
2. Read this entire document.
3. Re-read the current `EditorView.swift`, `EditorTextSystem.swift`, `EditorConfiguration.swift`, `DocumentEditorSplitView.swift`, and `WorkspaceCommands.swift` before editing.
4. Implement **Commit 1 only** first.
5. Run the package tests.
6. Request review before moving into delegate/AppKit wiring if the pure engine contract needs to change.

### Decisions already made — do not revisit

- no custom NSTextView subclass;
- existing coordinator remains sole delegate;
- Markdown-only fail-closed configuration;
- pure synchronous line-local engine;
- one contiguous edit per assist;
- UTF-16 ranges;
- no Markdown AST on hot path;
- no AppSettings UI;
- `⌘1…9` remains native tabs;
- headings use `⌃⌘1…6`, Paragraph `⌃⌘0`;
- markup characters with no selection do not auto-close merely because issue prose listed them; legacy behavior is the reference;
- marked-text composition is left untouched;
- task-list continuation resets checked state to unchecked;
- combined blockquote/list prefixes are supported;
- `=` selection wrapping is dropped;
- `insertMappedContent` is dropped;
- generic block-toggle commands are deferred.

### Stop and report instead of improvising if

- the AppKit delegate signatures differ on the actual Xcode 26 toolchain;
- `moveToLeftEndOfLine:` is not the command emitted by the macOS 26 Home/smart-home path during the manual verification;
- one `NSTextView.insertText` does not produce one undo unit in the mounted integration test;
- formatting shortcuts collide with an as-built command not identified here;
- the existing coordinator cannot receive `shouldChangeTextIn` without displacing another production delegate;
- any required behavior would force a Package.swift/dependency or architecture change.

Those are architecture-review events, not invitations to invent a parallel implementation.

---

## 22. Completion definition

Epic 10 is complete only when all of the following are true:

- [ ] list/ordered/task/blockquote/indent continuation behaves per §7;
- [ ] empty constructs terminate safely;
- [ ] structural pair completion/type-over/paired backspace works;
- [ ] selection wrapping works for the supported legacy/Markdown delimiters;
- [ ] Tab/Shift-Tab and smart Home work;
- [ ] Bold/Italic/Code and H1…H6/Paragraph commands work with non-conflicting shortcuts;
- [ ] every legacy `NSTextView+Autocomplete` API is marked ported/deferred/dropped in the parity ledger;
- [ ] non-Markdown formats receive zero E10 transformations;
- [ ] marked-text IME input receives zero E10 transformations;
- [ ] each text-mutating assist is exactly one undoable edit;
- [ ] one assist produces one binding publication;
- [ ] E18 external/model replacement semantics remain intact;
- [ ] existing package, build, lint and app gates are green;
- [ ] Release performance evidence exists and the `<50 ms` typing budget is not regressed;
- [ ] the Release dogfood matrix has been performed and concrete E10 defects are closed or explicitly recorded;
- [ ] README/spec status describes only what was actually validated.

Only then change the PR from draft and close #11.