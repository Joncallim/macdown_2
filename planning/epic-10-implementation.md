# EPIC-10 Implementation Architecture — Editing assists

> **Issue:** #11 — `[EPIC-10] Editing assists: list continuation, auto-pairing, indenting`
>
> **Status:** Architecture only. This is the binding implementation contract for the Epic 10 branch. Production code starts only after this document has been read end-to-end.
>
> **Branch:** `epic/10-editing-assists` → draft PR into `master`.
>
> **Baseline:** `48d852927ac19fd8d2eb0119750c528c3922eae1` — merged Epic 18 head.
>
> **Depends on:** E04 as built (`EditorView`, `EditorTextSystem`, TextKit 2 and per-window undo), E05 as built (highlighting attached to the same text system), E07/E08 as built (preview/outline consuming the editor binding), E18 as built (external-replacement guard and document-safety path).
>
> **No new third-party dependencies. No `Package.swift`, `project.yml`, session-schema, or CI-workflow change is expected.**

---

## 1. Product decision and reconciliation with the old issue

Epic 18 is merged, so the document-safety reason for postponing E10 is gone. E10 is now the editor-feel pass: it should make the existing source editor pleasant and Markdown-native without reopening already-working architecture.

The live repository is authoritative where the 19 July issue has drifted.

### 1.1 Stale shortcut assumption

The issue proposed `⌘1…6` for headings. The as-built native-tab model now owns `⌘1…9` for tab selection, and the layout menu owns `⌘⌥1…3`. E10 must preserve both.

Binding shortcuts:

- Bold — `⌘B`
- Italic — `⌘I`
- Inline Code — **`⌃⌘E`**
- Paragraph — `⌃⌘0`
- Heading 1…6 — `⌃⌘1…6`

`⌘E` is intentionally **not** taken: the existing editor uses AppKit's standard `NSTextFinder` responder-chain behavior, whose Find group includes “Use Selection for Find”. E10 leaves the entire SwiftUI `.textEditing` command group untouched.

### 1.2 Plain-text formatting menu

The editor explicitly sets `NSTextView.isRichText = false`; rich-text Font/Text formatting is not a MacDown document capability. E10 therefore replaces SwiftUI's `.textFormatting` command group with Markdown formatting commands rather than adding a duplicate top-level menu with competing Bold/Italic shortcuts.

Use:

```swift
CommandGroup(replacing: .textFormatting) {
    Button("Bold") { ... }
        .keyboardShortcut("b", modifiers: .command)
    Button("Italic") { ... }
        .keyboardShortcut("i", modifiers: .command)
    Button("Inline Code") { ... }
        .keyboardShortcut("e", modifiers: [.control, .command])
    Divider()
    Menu("Heading") { ... }
}
```

Do **not** replace `.textEditing`; that group owns Find, spelling/grammar, substitutions, transformations, and related standard editing behavior.

### 1.3 Settings are not part of E10

`AppSettings` is still a stub and E13 owns the Settings scene. E10 introduces a typed assist configuration and live application seam, with documented defaults, but does not build a settings pane or preference migration.

### 1.4 Debug mode is not a product-feel gate

Correctness still runs through package tests. Perceived typing feel and user-facing latency must be checked with a **Release app build**. Do not treat a Debug build's responsiveness as release evidence.

---

## 2. As-built constraints discovered from `master`

### 2.1 One NSTextView delegate already owns the input seam

`EditorView.Coordinator` is the current and only `NSTextViewDelegate`. It owns:

- `textDidChange` → live `NSTextView` text into the SwiftUI binding;
- selection callbacks → outline tracking;
- scroll callbacks → preview/outline sync;
- `isApplyingModelText` → model-to-view echo suppression.

**Binding rule:** E10 extends this coordinator. It does not install a second delegate, a delegate proxy, a notification-only parallel editing path, or a replacement view owner.

### 2.2 EditorTextSystem is the stable per-document editing object

`EditorTextSystem` owns one TextKit 2 stack and one per-document `UndoManager`. E18 added `isPerformingProgrammaticTextUpdate` so disk-driven replacement does not re-enter the user-edit binding path.

**Binding rule:** E10 edits are ordinary user edits. They continue through the normal `textDidChange` path and never reuse E18's programmatic-replacement path.

### 2.3 One edit publication already feeds everything else

Current user edit flow:

```text
NSTextView user edit
  → EditorView.Coordinator.textDidChange
  → Binding<String>
  → FileDocument value replacement / dirty state
  → highlighting
  → Markdown parse debounce
  → preview
  → outline
```

An E10 assist must enter that same flow exactly once. It must not separately update `FileDocument`, parser, highlighter, preview, outline, or recovery state.

### 2.4 Avoid a second whole-document string extraction

The existing post-edit binding path already reads the editor text. E10 must not call `NSTextView.string` again *before every keystroke* merely to decide whether to auto-pair or continue a list.

TextKit 2's `NSTextContentStorage` uses `NSTextStorage` as its default backing store. The E10 decision engine therefore reads from the live `NSTextStorage.mutableString` as an `NSString`-compatible, UTF-16-addressable source.

Add an internal `EditorTextSystem` accessor:

```swift
var assistTextSource: NSString? {
    guard let storage = contentStorage.attributedString as? NSTextStorage else {
        return textView.textStorage?.mutableString
    }
    return storage.mutableString
}
```

The exact spelling can be adjusted for the Xcode 26 SDK, but the contract is fixed:

- common-path E10 decisions must not materialize an additional full Swift `String` copy;
- the engine reads only the current line, selected line range, immediate neighbor characters, or explicit selection;
- if the expected live storage is unavailable, the production adapter **fails open to native AppKit behavior** and reports/asserts in Debug rather than falling back silently to an O(document) pre-keystroke copy.

Add a test that the current TextKit stack actually exposes an `NSTextStorage` backing object on the supported toolchain.

### 2.5 Format gating belongs at the app boundary and fails closed

`DocumentEditorSplitView` knows the active `FileFormat`. `WindowController` eagerly creates a text system with `EditorConfiguration.default` before the format-specific SwiftUI view mounts.

Therefore:

- `EditorConfiguration.default.editingAssists == .disabled`;
- only `document.format.id == "markdown"` receives `.markdownDefault`;
- HTML is not treated as Markdown merely because it also has rendered preview capability;
- Save As from Markdown → another format disables assists on the existing text system on the next configuration update;
- Save As into Markdown enables them.

### 2.6 E10 is file-format aware, not AST-context aware

E10 does **not** consult the debounced Markdown AST to determine whether the caret is inside front matter or a fenced code block. Doing so would put stale/asynchronous parser state into the synchronous keystroke path.

This means E10's assists are enabled throughout a Markdown file. This matches the scope/legacy model and is a conscious limitation. If Release dogfooding shows that list continuation inside fenced code blocks is materially harmful, file a focused follow-up rather than coupling E10 to stale parse state.

---

## 3. Non-negotiable architecture rules

1. **No `NSTextView` subclass.** No `keyDown` override, custom field editor, or alternate view class.
2. **One delegate.** `EditorView.Coordinator` remains the sole `NSTextViewDelegate`.
3. **Use AppKit's text-input pipeline.** Typed replacements use `textView(_:shouldChangeTextIn:replacementString:)`; command behavior uses `textView(_:doCommandBy:)`.
4. **Pure decision engine, thin AppKit adapter.** Decision logic is deterministic and synchronous.
5. **One contiguous text replacement per mutating assist.** No “delete marker then insert prefix” multi-step publication.
6. **All offsets are UTF-16.** `NSRange`, `NSString.length`, UTF-16-aware line/range helpers. Never `String.count` for editor positions.
7. **No full Markdown parse on the hot path.** No `MarkdownEngine`, syntax tree, or preview state dependency.
8. **No async work in the decision engine.** No `Task`, actor, debounce, sleep, or callback queue.
9. **No additional whole-document extraction on the common path.** Read local ranges from live text storage.
10. **IME marked text passes through untouched.** No pairing/wrapping/rewrite during composition.
11. **Programmatic/model replacements bypass E10.** Respect both existing re-entrancy guards.
12. **Markdown-only means Markdown-only.** Non-Markdown formats receive native AppKit behavior.
13. **Do not build E13.** Configuration now; settings UI later.
14. **Do not change native tabs, parser, highlighting, preview, external-file monitoring, FileTree, export, extension architecture, or session schema.**
15. **Do not weaken existing performance tests.** Release evidence is additive.

---

## 4. Data flow

### 4.1 Typed replacement

```text
NSTextInputClient / NSTextView
  → EditorView.Coordinator
      textView(_:shouldChangeTextIn:replacementString:)
  → guard model/E18/assist re-entrancy + marked text
  → MarkdownEditingAssistEngine.outcome(... live NSString source ...)
      ├── .passthrough → return true; AppKit performs original edit
      ├── .selection  → apply selection; return false
      └── .edit       → EditorTextSystem.applyAssistOutcome(...); return false
                           ↓
                         exactly one NSTextView.insertText(... replacementRange: ...)
                           ↓
                         nested shouldChange callback sees assist re-entrancy guard
                         and returns true without re-transforming
                           ↓
                         one normal textDidChange publication
```

### 4.2 Return / Tab / Shift-Tab / Backspace / Home

```text
NSTextView command
  → Coordinator.textView(_:doCommandBy:)
  → map supported selector to EditingAssistAction
  → pure engine
      ├── .passthrough → return false; AppKit handles command
      └── handled      → apply outcome; return true
```

Cocoa return semantics are binding: `doCommandBy` returns **true when E10 handled the command**, false when AppKit should continue.

### 4.3 Menu command

```text
WorkspaceCommands (.textFormatting replacement)
  → WindowCoordinator.performMarkdownEditingCommand(...)
  → key WindowController
  → active EditorTextSystem
  → same pure engine / same one-edit adapter
  → normal textDidChange path
```

Never synthesize key events to invoke a formatting command.

---

## 5. Types and exact contracts

### 5.1 `EditingAssistConfiguration.swift`

```swift
public struct EditingAssistConfiguration: Sendable, Equatable {
    public var isEnabled: Bool
    public var continuesMarkdownPrefixes: Bool
    public var completesMatchingCharacters: Bool
    public var convertsTabsToSpaces: Bool
    public var smartHome: Bool
    public var autoIncrementOrderedLists: Bool
    public var indentationWidth: Int

    public init(
        isEnabled: Bool,
        continuesMarkdownPrefixes: Bool = true,
        completesMatchingCharacters: Bool = true,
        convertsTabsToSpaces: Bool = true,
        smartHome: Bool = true,
        autoIncrementOrderedLists: Bool = true,
        indentationWidth: Int = 4
    )

    public static let disabled: EditingAssistConfiguration
    public static let markdownDefault: EditingAssistConfiguration
}
```

Rules:

- normalize `indentationWidth` to `1...8` in the initializer;
- `.disabled.isEnabled == false`;
- `.markdownDefault`: enabled, prefix continuation on, pairing on, spaces on, smart Home on, ordered increment on, width 4;
- no strikethrough preference is introduced here: legacy single-`~` wrapping is not GFM-correct and is deliberately not ported in E10.

### 5.2 `EditorConfiguration`

Add:

```swift
public var editingAssists: EditingAssistConfiguration
```

with initializer default `.disabled`.

`EditorConfiguration.default` explicitly stays disabled.

`EditorTextSystem.apply(_:)` stores the current assist configuration:

```swift
public private(set) var editingAssistConfiguration: EditingAssistConfiguration = .disabled
```

Do not duplicate this value in the SwiftUI coordinator.

### 5.3 `EditingAssistOutcome.swift`

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

`handledNoChange` is only for a deliberately consumed command. It is not an “implementation TODO” state.

### 5.4 `MarkdownEditingCommand.swift`

```swift
public enum MarkdownEditingCommand: Sendable, Equatable {
    case bold
    case italic
    case inlineCode
    case heading(level: Int)   // 1...6
    case paragraph
}
```

Reject invalid heading levels at the `EditorTextSystem` entry boundary; never pass invalid levels into the pure engine.

### 5.5 Internal action

```swift
enum EditingAssistAction: Equatable {
    case replacement(range: NSRange, string: String)
    case insertNewline
    case insertTab
    case insertBacktab
    case deleteBackward
    case smartHome
    case markdownCommand(MarkdownEditingCommand)
}
```

Marked-text state is handled in the adapter before entering the pure engine.

### 5.6 Pure engine

```swift
struct MarkdownEditingAssistEngine {
    static func outcome(
        for action: EditingAssistAction,
        text: NSString,
        selection: NSRange,
        configuration: EditingAssistConfiguration
    ) -> EditingAssistOutcome
}
```

First branch:

```swift
guard configuration.isEnabled else { return .passthrough }
```

The engine never mutates `text` and never asks for the whole Swift `String` value.

### 5.7 EditorTextSystem editing adapter

Add in `EditorTextSystem+EditingAssists.swift`:

```swift
private(set) var isPerformingEditingAssist: Bool

@discardableResult
func applyAssistOutcome(_ outcome: EditingAssistOutcome) -> Bool

@discardableResult
public func performMarkdownCommand(_ command: MarkdownEditingCommand) -> Bool
```

If stored properties cannot live in an extension, keep the boolean storage in `EditorTextSystem.swift` and the methods in the extension file.

`applyAssistOutcome`:

- `.passthrough` → return false;
- `.selection(range)` → clamp to live UTF-16 range, set selection, return true, no text undo entry;
- `.handledNoChange` → return true;
- `.edit(edit)`:
  1. guard the replacement range against current live text length;
  2. `textView.breakUndoCoalescing()` before the assist so it is not merged into prior ordinary typing;
  3. set `isPerformingEditingAssist = true` with `defer` reset;
  4. perform **exactly one** `textView.insertText(edit.replacementString, replacementRange: edit.replacementRange)`;
  5. set the clamped resulting selection;
  6. set the undo action name if native AppKit created an undo item;
  7. `textView.breakUndoCoalescing()` after the assist so subsequent typing starts a new coalescing group;
  8. return true.

Do not mutate `NSTextStorage` directly for the edit. The storage is the local read source; `NSTextView.insertText` is the write seam so delegate validation, undo, dirty-state publication, selection behavior, and TextKit notifications remain native.

Do not manually call `textDidChange`.

If the mounted AppKit integration test proves that one `insertText` plus `breakUndoCoalescing()` does not produce one undo step on Xcode/macOS 26, **stop and report an architecture event**. Do not fake atomic undo by manually registering a second independent undo action.

---

## 6. Coordinator wiring

### 6.1 Typed replacement hook

Implement the existing delegate method:

```swift
public func textView(
    _ textView: NSTextView,
    shouldChangeTextIn affectedRange: NSRange,
    replacementString: String?
) -> Bool
```

Guard order:

1. `system` exists;
2. `replacementString` non-nil, else native;
3. `!isApplyingModelText`;
4. `!system.isPerformingProgrammaticTextUpdate`;
5. `!system.isPerformingEditingAssist`;
6. configuration enabled;
7. IME safety:

```swift
let marked = textView.markedRange
if textView.hasMarkedText ||
   (marked.location != NSNotFound && NSIntersectionRange(marked, affectedRange).length > 0) {
    return true
}
```

8. live `assistTextSource` exists, otherwise fail open.

Then call `.replacement(range:string:)`. If handled, apply and return false. Otherwise return true.

### 6.2 Command hook

Implement:

```swift
public func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool
```

Map only:

- `insertNewline:` → `.insertNewline`
- `insertTab:` → `.insertTab`
- `insertBacktab:` → `.insertBacktab`
- `deleteBackward:` → `.deleteBackward`
- `moveToLeftEndOfLine:` → `.smartHome`

Everything else returns false immediately.

For smart Home, `moveToLeftEndOfLine:` is the legacy/expected AppKit command seam. The Release manual gate must confirm the supported macOS 26 key-binding path reaches it. If it emits a different **documented NSText command selector**, add that selector to the same action. Do not introduce raw `keyDown` interception.

---

## 7. Local UTF-16 helpers

The engine may add small internal helpers, but they must stay range-local.

Required primitives:

- clamp a requested `NSRange` to `0...text.length`;
- current line start/end/content-end around a UTF-16 location;
- previous/next composed scalar around a UTF-16 boundary without treating half of a surrogate pair as punctuation;
- substring for a known local range;
- selected logical line range;
- first non-whitespace offset in a local line.

Use `NSString`/`NSMutableString` APIs and local substrings. Do not call `components(separatedBy:)` on the entire document or compile/run a whole-document regex on each keystroke.

Boundary classification for pair completion uses whitespace/newline/punctuation, but must inspect a complete neighboring Unicode scalar/composed sequence. Emoji/CJK neighbors are ordinary non-boundary text unless the actual scalar is classified as punctuation/space.

---

## 8. Return / list / task / blockquote continuation

### 8.1 Unified line prefix

Parse from the current line start to the caret into one value:

```swift
struct MarkdownLinePrefix: Equatable {
    let indentation: String
    let blockquotePrefix: String
    let listMarker: ListMarker?
    let taskMarker: TaskMarker?
    let contentRangeInLine: NSRange
}

enum ListMarker: Equatable {
    case unordered(Character)           // -, +, *
    case ordered(rawDigits: String)     // digits + '.'
}
```

`TaskMarker` recognizes `[ ]`, `[x]`, `[X]`; continuation always emits `[ ]`.

Grammar order:

```text
[indentation]
[zero or more `>` markers, preserving each marker's optional following space]
[optional unordered marker OR decimal-digits + '.' + whitespace]
[optional task marker + whitespace]
[content]
```

Support composition:

- `- item` → `- `
- `  4. item` → `  5. `
- `> quote` → `> `
- `> - item` → `> - `
- `> - [x] done` → `> - [ ] `
- indentation-only content → same indentation on the new line.

This intentionally improves the legacy separate list/blockquote handlers: composed prefixes are treated as one Markdown structure.

### 8.2 Ordered-number safety

Never parse ordered markers with a force-converting integer.

For auto-increment:

- if `rawDigits` can be represented and incremented safely, increment it;
- preserve zero-padding width where possible (`009.` → `010.`);
- if it cannot be represented or increment would overflow, repeat the exact original digits rather than trap or delete content.

When auto-increment is off, repeat `rawDigits` exactly.

### 8.3 Normal continuation

Only for collapsed selection.

For non-empty content before caret:

- unordered → newline + outer prefixes + same marker + space;
- ordered → newline + outer prefixes + safe next/repeated number + `. `;
- task → same list prefix + `[ ] `;
- blockquote-only → newline + indentation + exact quote prefix;
- indentation-only line with non-whitespace content → newline + indentation;
- no recognized prefix → `.passthrough`.

If Return splits a line, preserve the tail exactly once.

### 8.4 Empty-construct termination

“Empty” means the recognized inner construct has no non-whitespace content before the caret.

- empty list/task → exit one list level;
- empty list inside quote → remove list/task marker but keep quote context;
- empty quote-only line → exit quote;
- whitespace-only line without list/quote construct → native newline.

Calculate the entire result first and perform one replacement. Do not delete a marker and then separately insert a newline.

### 8.5 Existing next-prefix suppression

If splitting immediately before an already-present exact continuation prefix, do not duplicate it. Decide this from the original live text before mutation.

### 8.6 Line endings

Use local line metadata. Preserve CRLF when the active line has an observable CRLF separator; otherwise use `\n`, matching normal NSTextView insertion at a final line. Never leak a literal `\r` into prefix text.

---

## 9. Matching characters and Markdown delimiters

E10 must satisfy the issue's markup-pairing requirement *and* avoid breaking normal Markdown list entry.

### 9.1 Structural pair table

Port as data:

- `(` → `)`
- `[` → `]`
- `{` → `}`
- `<` → `>`
- `'` → `'`
- `"` → `"`
- `（` → `）`
- `「` → `」`
- `『` → `』`
- curly single/double quote pairs
- single/double guillemets
- East Asian single/double angle-bracket pairs.

### 9.2 Structural no-selection pairing

For one supported opener with collapsed selection:

- next character is end-of-document or whitespace/newline/punctuation;
- symmetric quote opener additionally requires previous boundary/end;
- asymmetric brackets keep the legacy permissive previous-character behavior.

Insert opener+closer in one edit and leave caret between.

### 9.3 Markdown symmetric delimiters

The issue explicitly calls out `*`, `_`, backtick, and strong `**`. These are **not** handled identically to structural brackets.

#### `*`

- At the first non-whitespace position of a line, **do not auto-pair** a single `*`; allow native insertion so `* ` unordered-list typing remains natural.
- Else, when at a word/punctuation boundary suitable for opening emphasis, typing `*` inserts `**` with caret between.
- If the caret is between the just-representable local shape `*|*` and the user types a second `*`, upgrade in one replacement to `**|**` so strong emphasis can be typed naturally.

#### `_`

- Pair only at a boundary; never auto-pair intra-word underscore.
- The local `_ |_` equivalent may upgrade to `__|__` on a second underscore.

#### backtick

- A single backtick may pair to `` `|` `` when pairing is enabled.
- Do not invent multi-backtick fence escalation in E10.

These rules are local and state-free. No hidden “paired character registry” is persisted across edits.

### 9.4 Type-over closer

For structural pairs and symmetric Markdown delimiters, if the typed character is already the immediate next delimiter character, move selection one UTF-16 unit right and suppress insertion.

For a strong closer `**`, two successive typed `*` characters naturally move over the two existing closing characters one at a time.

No undo item for a selection-only move.

### 9.5 Selection wrapping

When replacement range is non-empty:

- structural opener → mapped close;
- `*` → `*selection*`;
- `_` → `_selection_`;
- backtick → `` `selection` ``.

After first `*` or `_` wrap, keep the original logical content selected. A second typed same delimiter therefore wraps the still-selected logical content again, producing strong `**selection**` / `__selection__` naturally.

Deliberate non-ports:

- legacy `=` wrapping — dropped; current product has no matching legacy highlight/underline extension contract;
- legacy single-`~` wrapping — dropped; single tilde is not the modern GFM strikethrough delimiter. E10 does not invent a strikethrough command that issue #11 did not request.

### 9.6 Paired Backspace

Collapsed caret between an adjacent recognized auto-pair removes both characters in one edit:

- structural pair;
- single `*|*`, `_|_`, or `` `|` ``.

For `**|**`, one Backspace may reduce one adjacent star pair to `*|*`; a second Backspace removes the remaining pair. Do not build hidden pair ownership state.

Ordinary Backspace passes through.

### 9.7 IME safety

If `hasMarkedText` is true or the affected range intersects a valid marked range, E10 does nothing. This is stricter and safer than legacy MacDown's partial ASCII exception and is recorded as an intentional parity deviation.

---

## 10. Tab / Shift-Tab indentation

### 10.1 Collapsed Tab

If `convertsTabsToSpaces`:

```text
spaces = indentationWidth - (column % indentationWidth)
```

Modulo zero inserts a full indentation width.

Column is UTF-16 distance from local line start; spaces are ASCII.

If conversion disabled, pass through to native Tab behavior.

### 10.2 Selected Tab

Replace the selected logical line range once:

- prefix each selected real line with exactly `indentationWidth` spaces;
- do not indent a synthetic trailing empty line caused solely by selection ending immediately after newline;
- remap selection by exact per-line UTF-16 deltas.

### 10.3 Selected Shift-Tab

For each selected line remove:

1. one leading tab, else
2. up to `indentationWidth` leading spaces.

One replacement over the selected line range; one undo step.

### 10.4 Collapsed Shift-Tab

Within leading indentation, remove one tab or spaces back to previous indentation stop, capped at width.

If nothing can be unindented, pass through so E10 does not globally swallow responder traversal.

---

## 11. Smart Home

Only when Markdown assists and `smartHome` are enabled.

For current line:

1. compute line start;
2. compute first non-whitespace UTF-16 offset;
3. if caret is elsewhere, move to first non-whitespace;
4. if already there, move to physical line start;
5. all-whitespace line → line start.

For a non-empty selection, collapse to the computed target; no Shift+Home extension behavior is introduced in E10.

Use the AppKit text command seam, not key codes.

---

## 12. Markup commands

### 12.1 Inline toggles

- Bold → `**selection**`
- Italic → `*selection*`
- Inline Code → `` `selection` ``

If selection is already exactly surrounded by the command's delimiter, remove it and keep the logical selection.

Empty selection inserts delimiters and leaves caret inside.

Preserve the legacy emphasis ambiguity rule:

- `***selection***` counts as surrounded by a single outer `*` for italic toggle;
- `**selection**` alone does not count as single-star italic markup.

All toggles are one contiguous replacement.

### 12.2 Headings / Paragraph

Commands apply to every logical line touched by selection.

For each processed non-empty line:

1. remove one existing leading ATX heading prefix matching 1…6 `#` plus at least one space/tab;
2. Heading N prepends exactly N `#` + one space;
3. Paragraph prepends nothing.

Rules:

- preserve content after the removed prefix verbatim;
- skip whitespace-only lines inside a multi-line selection;
- if the only targeted line is blank, Heading N inserts the heading prefix so typing can begin immediately;
- do not convert Setext underline syntax in E10;
- replace the complete affected line range once;
- remap selection using exact per-line UTF-16 deltas.

### 12.3 Command bridge

Create `MacDown2/MacDown2/WindowCoordinator+Editing.swift`:

```swift
var canPerformMarkdownEditingCommand: Bool { get }

@discardableResult
func performMarkdownEditingCommand(_ command: MarkdownEditingCommand) -> Bool
```

Resolve key `WindowController`, active Markdown document, active tab identity, and existing `EditorTextSystem`.

Before mutating, verify:

- document format id is `markdown`;
- text system exists;
- assist configuration enabled;
- `NSApp.keyWindow?.firstResponder === textSystem.textView` or first responder is a descendant/responder state proven to be the active editor for this exact window.

Do not apply a formatting command to a stale selection when focus is in sidebar, Find UI, or another native tab.

`WorkspaceCommands` may use `canPerformMarkdownEditingCommand` for disabled state, but the command bridge repeats all guards. Menu enablement is not a safety boundary.

---

## 13. App format wiring

Only `DocumentEditorSplitView.editorConfiguration` decides file-format enablement:

```swift
private var editorConfiguration: EditorConfiguration {
    var config = EditorConfiguration.default
    config.scrollsPastEnd = false
    config.editingAssists = document.format.id == "markdown" ? .markdownDefault : .disabled
    return config
}
```

No `AppSettings` changes.

---

## 14. Legacy parity ledger

Issue #11 cannot close until implementation updates this table to actual shipped status.

| Legacy `NSTextView+Autocomplete` API | E10 disposition |
|---|---|
| `substringInRange:isSurroundedByPrefix:suffix:` | Port as internal markup-surround helper incl. `*` vs `**`/`***` rule |
| `insertSpacesForTab` | Port; configurable width 1…8 |
| `completeMatchingCharactersForTextInRange` | Port/extend through typed replacement engine |
| `completeMatchingCharacterForText:atLocation:` | Port structural pair/type-over; extend with scoped Markdown delimiter pairing required by issue #11 |
| `wrapTextInRange` | Port as generic one-replacement wrapper |
| `wrapMatchingCharactersOfCharacter` | Port structural + `*`/`_`/backtick; drop legacy `=` and single-`~` behavior |
| `deleteMatchingCharactersAround` | Port; extend paired deletion to E10's symmetric Markdown auto-pairs |
| `unindentForSpacesBefore` | Port; configurable width |
| `toggleForMarkupPrefix:suffix:` | Port for Bold/Italic/Code |
| `toggleBlockWithPattern:prefix:` | Deliberately deferred — generic quote/list toggle commands are not issue #11 scope |
| `indentSelectedLinesWithPadding` | Port |
| `unindentSelectedLines` | Port |
| `insertMappedContent` | Drop — legacy bundled data-map helper is not a current editor requirement |
| `completeNextListItem` | Port; extend tasks and composed quote/list prefixes |
| `completeNextBlockquoteLine` | Port into unified prefix parser |
| `completeNextIndentedLine` | Port |
| `makeHeaderForSelectedLinesWithLevel` | Port as H1…H6 + Paragraph |
| legacy partial marked-text behavior | Replace with full marked-text pass-through for IME safety |

---

## 15. Exact file layout

Expected new files:

```text
MacDown2/Packages/MacDownKit/Sources/EditorCore/
  EditingAssistConfiguration.swift
  EditingAssistOutcome.swift
  MarkdownEditingCommand.swift
  MarkdownEditingAssistEngine.swift
  EditorTextSystem+EditingAssists.swift

MacDown2/Packages/MacDownKit/Tests/EditorCoreTests/
  EditingAssistPairingTests.swift
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
planning/epic-10-implementation.md
planning/epics/EPIC-10-editing-assists.md   # completion status only at end
README.md                                  # completion status only at end
```

Must **not** change without an explicit architecture-review comment first:

```text
MacDown2/Packages/MacDownKit/Package.swift
MacDown2/project.yml
.github/workflows/ci.yml
MarkdownEngine/**
Highlighting/**
Preview/**
FileTree/**
E18 monitor/controller architecture
Workspace session schema
```

---

## 16. Required tests

Use table-driven tests where only marker/pair inputs vary.

### 16.1 Live TextKit source seam

- current `TextKitStack` exposes `NSTextStorage` / mutable-string backing on Xcode/macOS 26;
- E10 source accessor reads local text without calling a new full-document Swift-string snapshot API;
- unavailable source fails open, never crashes or transforms blindly.

### 16.2 Structural pairing

- every structural opener pairs at a valid boundary;
- opener before ordinary alphanumeric next character does not pair;
- symmetric quote requires previous boundary;
- closer before identical existing closer moves selection without duplicate;
- selected content wraps for each structural opener;
- paired Backspace deletes both once;
- ordinary Backspace passes through;
- emoji/CJK neighbors prove UTF-16 and scalar-boundary correctness.

### 16.3 Markdown delimiter pairing

- `*` in prose boundary → `*|*`;
- `*` at first non-whitespace line position does **not** pair, preserving `* ` list typing;
- second `*` inside `*|*` upgrades to `**|**`;
- `_` boundary pairs; intra-word `_` does not;
- second `_` upgrades to strong equivalent;
- backtick pairs;
- type-over works for symmetric closing delimiters;
- selection wrapping keeps logical selection selected;
- second wrapping of still-selected content produces strong delimiters;
- `=` and `~` receive native/pass-through behavior;
- paired Backspace on Markdown pair behaves as §9.6.

### 16.4 IME

- `hasMarkedText` path bypasses engine;
- valid marked-range intersection bypasses engine;
- `NSNotFound` marked range is never passed into `NSIntersectionRange` as a real range;
- final normal input after composition still works natively.

### 16.5 Newline / prefixes

- `-`, `+`, `*` continue unchanged;
- ordered `1.` → `2.`;
- multi-digit increment;
- leading-zero increment preserves width;
- huge/overflowing digit string repeats safely;
- increment-disabled repeats exact digits;
- `[ ]`, `[x]`, `[X]` continue as `[ ]`;
- blockquote spelling/spacing preserved;
- nested quotes preserved;
- `> - item` → `> - `;
- `> - [x] item` → `> - [ ] `;
- indentation-only content continues indent;
- plain line passes through;
- empty list/task exits list;
- empty list in quote exits list but retains quote context;
- empty quote exits quote;
- selection present passes through;
- mid-line Return preserves tail exactly once;
- existing matching next prefix not duplicated;
- CRLF fixture does not leak `\r`.

### 16.6 Indentation

- width 4 columns 0…4 insert 4,3,2,1,4 spaces;
- widths 2 and 8;
- selected one/multi-line indent;
- selection ending at newline does not create synthetic padded line;
- selected Shift-Tab removes one tab or configured spaces;
- collapsed Shift-Tab to previous stop;
- no removable indent passes through;
- UTF-16 selection around emoji/CJK remaps correctly.

### 16.7 Smart Home

- indented line first trigger → first non-whitespace;
- second trigger → physical line start;
- unindented line → start;
- all-whitespace line → start;
- previous lines containing emoji/CJK do not corrupt current UTF-16 position.

### 16.8 Formatting

- Bold wrap/toggle off;
- Italic wrap/toggle off;
- Italic does not strip only-strong `**`;
- Italic recognizes outer single stars in `***...***`;
- Inline Code wrap/toggle off;
- empty selection caret inside delimiters;
- H1…H6 replace existing ATX level rather than stack;
- Paragraph strips ATX prefix;
- multi-line heading skips blank interior lines;
- selection tracks same logical content after positive/negative per-line shifts;
- CRLF range remains valid.

### 16.9 Disabled / Save As gating

Release blocker:

- `.disabled` → passthrough for every action family;
- `EditorConfiguration.default` disabled;
- Markdown config enabled only for exact format id;
- live config enabled → disabled stops the very next assist;
- Save As `.md` → `.txt` behavior loses E10 transformations;
- Save As back into Markdown re-enables them.

### 16.10 One action → one publication

Mounted coordinator/text-system integration test with binding counter:

- one pair assist → one binding write with final text;
- one list continuation → one binding write;
- one formatting command → one binding write;
- no intermediate half-applied value escapes.

### 16.11 Undo / redo

Mounted AppKit tests for representative mutation classes:

- pair insertion;
- list continuation;
- selected-line indent;
- Bold toggle;
- heading conversion.

For each:

1. capture original text/selection;
2. perform assist;
3. **one Undo** restores original text;
4. **one Redo** restores transformed text;
5. no intermediate half-edit exists.

Type-over and smart Home do not add text undo entries.

### 16.12 E18 / model replacement regressions

Exercise:

- `updateNSView` model push (`isApplyingModelText`);
- `replaceTextFromExternal` (`isPerformingProgrammaticTextUpdate`).

Neither may trigger E10 even when replacement text contains a pair/list marker.

### 16.13 Existing integration remains green

Do not modify expectations to make E10 pass if these regress:

- highlighting attachment/language switching;
- preview update;
- outline update;
- selection/scroll restore;
- existing EditorCore <50 ms keystroke performance test.

---

## 17. Performance contract

### 17.1 Structural hot-path guarantee

Review must be able to prove the common no-op input path:

- reads live backing storage;
- inspects only immediate neighbors/current line;
- does not copy/scan the full document;
- does not parse Markdown;
- allocates no Task;
- runs no document-wide regex.

Selection-line commands may scale with the selected line range; they must not scale with unrelated document text.

### 17.2 Measurements

Keep the existing `EditorPerformanceTests.keystroke()` `<50 ms` gate.

Add Release measurements:

1. **No-op assist decision on a 1 MB document:** ordinary alphanumeric replacement near a representative line. Record measured value; target substantial headroom (<5 ms on development hardware) but avoid a flaky cross-runner hard threshold if runner variance proves high.
2. **Handled assist + existing viewport path on 1 MB:** pair or newline continuation through actual `EditorTextSystem` adapter remains under the existing 50 ms user-facing budget.
3. Compare against a baseline run with assists disabled so the PR records incremental E10 overhead.

Use `swift test -c release` for performance evidence. Do not make user-facing claims from Debug.

---

## 18. UI / Release dogfood gate

### 18.1 XCUITest

`EditingAssistsUITests.swift` minimum:

1. launch/open Markdown fixture;
2. focus editor;
3. type `- item` + Return;
4. assert continued `- ` appears;
5. type more text proving normal input continues after handled Return.

If the existing accessibility seam is stable, also open `.txt`, type `(`, verify no synthetic `)`.

`build-for-testing` compilation is not proof that UI behavior ran. Record actual local macOS 26 execution separately.

### 18.2 Deterministic Release build

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

### 18.3 Manual matrix

In Release:

- several minutes ordinary prose typing: no synthetic characters/lag;
- unordered/ordered/task continuation + termination;
- `* ` list typing specifically confirms asterisk pairing does not fight bullets;
- nested blockquote + list/task;
- bracket/quote pair open/type-over/backspace;
- emphasis/strong/backtick auto-pair path;
- selection wrapping;
- Tab/Shift-Tab single/multi-line;
- smart Home;
- Bold/Italic/Code and H1…H6/Paragraph menu commands;
- `⌘E` still performs standard Find-selection behavior rather than Inline Code;
- native-tab `⌘1…9` unchanged;
- one Undo per representative assist;
- Save As Markdown → text disables assists, and back enables;
- at least one IME composition path is untouched;
- preview/highlighting/outline remain responsive;
- fenced code/front-matter behavior is observed and recorded as the known format-only gating limitation, not silently “fixed” by adding parser coupling.

Dogfood findings that are genuinely E10 bugs are fixed on this PR. Unrelated feature ideas become follow-up issues.

---

## 19. Ordered implementation commits

Commits 1–4 are serial. Do not parallelize them.

### Commit 1 — pure engine + exhaustive pure tests

Only:

- `EditingAssistConfiguration.swift`
- `EditingAssistOutcome.swift`
- `MarkdownEditingCommand.swift`
- `MarkdownEditingAssistEngine.swift`
- pure pairing/newline/indent/format/Home tests.

Use `NSString` test sources. No EditorView/app changes.

Exit gate: behavior contract green, including overflow and UTF-16 cases.

### Commit 2 — configuration + live-storage/format seam

Only:

- `EditorConfiguration.swift`
- `EditorTextSystem.swift` local text-source/config readout
- `DocumentEditorSplitView.swift`
- storage/config/non-Markdown tests.

Exit gate: current TextKit stack exposes expected live storage; default fail-closed; format transitions tested.

### Commit 3 — delegate interception + one-edit/undo adapter

Only:

- `EditorView.swift`
- `EditorTextSystem+EditingAssists.swift`
- coordinator/system integration tests
- one-publication, undo, re-entrancy, marked-text, and E18 regression tests.

Exit gate: one assist → one AppKit edit → one binding publication; one Undo; native input unaffected.

### Commit 4 — app Markdown formatting commands

Only:

- `WindowCoordinator+Editing.swift`
- `WorkspaceCommands.swift`
- command integration tests where practical.

Use `CommandGroup(replacing: .textFormatting)`; leave `.textEditing` untouched.

Exit gate: `⌘B`, `⌘I`, `⌃⌘E`, `⌃⌘0…6`; `⌘E`, `⌘1…9`, and `⌘⌥1…3` preserved.

### Commit 5 — perf/UI/Release evidence + implementation record

- E10 performance tests/evidence;
- `EditingAssistsUITests.swift`;
- focused fixes from Release dogfood;
- update this document with implementation notes/deviations;
- mark Epic/README implemented only after all gates are real.

Keep architecture/implementation/review boundaries visible while PR is under review.

---

## 20. Validation before leaving draft

Run and record:

```bash
# Debug correctness
cd MacDown2/Packages/MacDownKit
swift build
swift test

# Release + performance evidence
swift build -c release
swift test -c release

# Concurrency regression pass
swift test --sanitize=thread

# App / CLI / UI-test build
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

Then run §18 Release dogfood matrix.

Do not mark ready if any is true:

- non-Markdown receives an E10 assist;
- marked text is transformed;
- one assist requires two Undos;
- one assist publishes multiple binding states;
- `⌘E` Find behavior or native-tab shortcuts regress;
- existing <50 ms keystroke test regresses;
- E18 external/model replacement path changes behavior;
- Release dogfooding shows ordinary typing interference.

---

## 21. Orthogonal review checklist

Reviewer must explicitly audit independent dimensions.

### 21.1 Correctness

- every range is UTF-16;
- no surrogate-half classification;
- line-start/end/trailing-newline behavior;
- ordered integer overflow is safe;
- zero-padding behavior is deterministic;
- selection remap after multi-line prefix changes;
- empty construct termination;
- nested quote/list/task composition;
- asterisk list-entry suppression;
- strong-emphasis upgrade/type-over sequence.

### 21.2 AppKit semantics

- delegate Bool return semantics correct;
- nested assist insertion bypasses re-transformation;
- one `textDidChange`, not zero/two;
- writes go through `NSTextView.insertText`, not direct storage mutation;
- `breakUndoCoalescing()` isolation verified by real undo test;
- selection-only actions do not dirty text or add text undo.

### 21.3 Integration/safety

- marked text bypass;
- model/E18 replacement bypass;
- fail-closed default;
- Save As format transition;
- preview/highlight/outline consume only final text;
- no retain cycle between coordinator/system;
- `.textEditing` command group preserved;
- `.textFormatting` replacement does not create duplicate shortcut owners.

### 21.4 Performance

- no pre-keystroke whole-document String extraction added by E10;
- local live-storage reads only;
- no document-wide regex/AST/Task;
- selection operations scale with selected text only;
- Release evidence used for feel/performance claims.

### 21.5 Scope

Reject opportunistic additions:

- link/image autocomplete;
- snippets;
- generic command palette;
- E13 settings UI;
- parser/highlighter refactor;
- native-tab changes;
- extension/plugin work;
- AST-aware fenced-code suppression.

---

## 22. Lower-tier implementation handoff

### Start

1. Use existing `epic/10-editing-assists` branch.
2. Read this document completely.
3. Re-read current `EditorView.swift`, `EditorTextSystem.swift`, `EditorConfiguration.swift`, `DocumentEditorSplitView.swift`, `WorkspaceCommands.swift`, and legacy `NSTextView+Autocomplete` before editing.
4. Implement **Commit 1 only**.
5. Run package tests.
6. Request focused review before changing the pure engine contract.

### Decisions already made — do not revisit

- no custom `NSTextView` subclass;
- existing coordinator is sole delegate;
- live `NSTextStorage.mutableString`/NSString-style source, no extra whole-document pre-keystroke copy;
- Markdown-only fail-closed configuration;
- pure synchronous local engine;
- one contiguous write per mutating assist;
- UTF-16 ranges only;
- no Markdown AST on hot path;
- no settings UI;
- `⌘1…9` stays native tabs;
- `⌘E` stays Find; Inline Code is `⌃⌘E`;
- `.textFormatting` is replaced; `.textEditing` is preserved;
- asterisk auto-pair is suppressed at line-start bullet position;
- second `*`/`_` inside an empty local pair upgrades to strong;
- task continuation resets checked → unchecked;
- combined quote/list/task prefixes supported;
- legacy `=` and single-`~` wrapping dropped;
- `insertMappedContent` dropped;
- generic block-toggle commands deferred;
- marked text is untouched;
- no AST-aware fenced-code/front-matter gating in E10.

### Stop and report instead of improvising if

- Xcode 26 delegate method signatures differ;
- current TextKit stack does not expose the expected `NSTextStorage` backing source;
- Home emits no usable documented text command selector;
- one `insertText` + undo-coalescing break cannot produce one undo step;
- another shipped command owns one of the revised shortcuts;
- coordinator cannot receive `shouldChangeTextIn` without displacing another production delegate;
- required behavior would force dependency/project/CI/session changes.

Those are architecture-review events.

---

## 23. Completion definition

Epic 10 is complete only when:

- [ ] unordered/ordered/task/blockquote/indent continuation works;
- [ ] empty constructs terminate safely;
- [ ] structural pair completion/type-over/paired Backspace works;
- [ ] `*`/`_`/backtick pairing satisfies issue #11 without breaking `* ` list entry;
- [ ] selection wrapping works;
- [ ] Tab/Shift-Tab and smart Home work;
- [ ] Bold/Italic/Code and H1…H6/Paragraph commands work;
- [ ] `⌘E`, native tabs, and layout shortcuts remain intact;
- [ ] legacy parity ledger is updated to actual implementation;
- [ ] non-Markdown gets zero E10 transformations;
- [ ] marked-text IME gets zero transformations;
- [ ] each mutating assist is one undoable edit;
- [ ] each assist produces one binding publication;
- [ ] E18 external/model replacement semantics remain intact;
- [ ] Debug + Release package/build/lint gates pass;
- [ ] existing <50 ms keystroke gate is not regressed;
- [ ] Release incremental E10 performance evidence is recorded;
- [ ] Release dogfood matrix is performed and E10 defects resolved/recorded;
- [ ] README/spec claim only what was actually validated.

Only then mark the PR ready and close #11.