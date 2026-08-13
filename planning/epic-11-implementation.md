# EPIC-11 Implementation Plan — Multi-format support

> **Issue:** #12 — `[EPIC-11] Multi-format support: JSON tools, HTML preview toggle, language registry completion`
>
> **Status:** Planning pass complete; implementation has not started. This document is the binding contract for the implementation PR(s).
>
> **Branch:** `epic/11-multi-format` → `master`.
>
> **Baseline:** current `master` after Epic 10 and Epic 18.
>
> **Depends on:** E05 as built (`GrammarRegistry`), E07 as built (`Preview`/Textual Markdown preview), E08 as built (`OutlineUI`), and E18 as built (document/recovery/external-file safety).

## 1. Planning disposition

The issue is directionally correct but was too broad to implement safely without additional contracts. This plan makes the work reviewable in sequential gates:

1. format/capability contracts and registry consistency;
2. JSON diagnostics, outline, and deterministic formatting;
3. native editor publication and workspace commands;
4. HTML source/rendered preview with explicit resource security;
5. format-neutral preview/outline integration and persistence;
6. one grammar dependency at a time;
7. release, UI, performance, and dependency proof.

No later slice may advertise a format whose parser, grammar, resources, or preview behavior is not buildable and tested. Unsupported formats must degrade to an explicit no-preview/no-highlighting state, never silently inherit a Markdown parser or renderer.

## 2. As-built constraints and ownership

The implementation must preserve these existing boundaries:

- `FileFormat`/`FileFormatRegistry` owns document identity, extensions, UTTypes, encoding, highlight language, and preview capability.
- `GrammarRegistry` owns Tree-sitter language construction, query resources, caching, and failure isolation. `ParseEngine` remains Markdown-only.
- `EditorTextSystem` and the existing AppKit delegate own native text edits, selection, undo, and binding publication. JSON formatting must enter this path exactly once.
- `Preview` owns renderer policy and typed preview requests. The current `WKWebView` host is app-level in `DocumentEditorSplitView`; moving it into the package is not implicit in this Epic.
- `OutlineUI` currently consumes Markdown heading data. JSON must use a format-neutral outline snapshot/adapter; it must not fabricate a Markdown AST.
- `WorkspaceSession` is version 1 and owns tabs, identities, and recovery state. Preview mode may be added only as an optional, versioned field and must never alter document/recovery identity.
- `WorkspaceModel` owns format commands, generation checks, save/recovery publication, and format transitions. Views must not parse extensions or mutate document text directly.
- Markdown editing assists remain Markdown-only. JSON and HTML receive native text behavior unless a later Epic explicitly adds language-specific assists.

## 3. Contracts that must be fixed before implementation

### 3.1 Format and preview capability

Replace implicit renderer inference with typed capability/renderer identity. Every format declares an explicit outcome:

```swift
enum PreviewCapability: Sendable, Equatable {
    case none
    case markdown
    case htmlSourceAndRendered
    case jsonOutline
}

enum PreviewMode: String, Codable, Sendable {
    case source
    case rendered
    case outline
}
```

For each capability define: default mode, source of truth, per-tab ownership, session persistence (or explicit non-persistence), Save As invalidation, loading/error/empty states, accessibility identifiers, and jump/scroll rules. Markdown, HTML, JSON, and source-only formats must have routing tests.

### 3.2 JSON diagnostics

Expose a stable value type rather than Foundation parser errors across actors:

```swift
struct JSONDiagnostic: Sendable, Equatable {
    let message: String
    let line: Int       // 1-based physical line
    let column: Int     // 1-based UTF-16 column
    let range: Range<Int>?
}
```

Define behavior for empty input, top-level scalars, duplicate keys, malformed UTF-8, BOM, CRLF, tabs, and error ranges. Diagnostics are generated from an immutable text snapshot and carry a document revision/generation. Rapid valid→invalid→valid edits must publish only the latest result. Invalid JSON never replaces source text or clears a valid outline without an explicit policy decision.

### 3.3 JSON outline

Use a concrete, source-neutral outline model rather than `AnyHashable` IDs or a fake Markdown document:

```swift
struct ContentOutlineItem: Sendable, Equatable, Identifiable {
    let id: String
    let title: String
    let lineRange: Range<Int>
    let sourceRange: Range<Int> // UTF-16 offsets
    let children: [ContentOutlineItem]
}
```

IDs must encode object-key path and array index path, disambiguate duplicate keys deterministically, and remain remappable across edits/formatting. Define labels for scalar roots, empty containers, arrays, and objects; set a tested depth/node policy; preserve collapse/selection/jump behavior; and define what happens on invalid JSON.

### 3.4 JSON formatting

Formatting is deterministic and operates only on valid JSON. Capture immutable text plus document generation/revision, compute off the main actor, and reject the result if the document or external-file baseline changed. Apply output as one contiguous native editor replacement, producing exactly one undo group, one binding publication, and normal dirty/recovery updates.

Specify:

- object key sort order (Unicode scalar order, recursively for nested objects);
- arrays retain order;
- duplicate-key behavior (preserve/reject; never silently merge);
- scalar roots;
- indentation and trailing-newline policy;
- CRLF/LF and BOM preservation;
- non-ASCII escaping policy;
- behavior when formatting is requested for invalid JSON.

### 3.5 HTML preview security and resources

The existing WebKit host disables JavaScript and loads with `baseURL: nil`. The Epic must make an explicit decision before implementation:

- **Default v1 policy:** scripts, network access, popups, downloads, message handlers, forms, clipboard access, storage/cookies, and external navigation are disabled or denied. No JavaScript bridge is exposed.
- If scripts are deliberately enabled, document the exact isolation policy and tests; a WKWebView is not equivalent to the app's OS sandbox.
- Relative resources may load only from an approved document directory after explicit security-scoped access. Untitled HTML has no local resource root.
- Reject `../` escape, outside-root symlinks, remote URLs, `javascript:` URLs, iframe escapes, popups, downloads, and navigation outside the approved policy.
- Save As, rename, delete, and preview disposal must balance security-scope access and cancel stale loads.

The HTML hardening path must not rely solely on raw string search that can mistake `<head>` text inside comments or script strings for markup. Use a parser/sanitizer or a wrapper plus WebKit policy controls, with adversarial fixtures.

HTML reload is latest-request-wins, revision-tagged, cancellation-safe, and triggered on save/relevant source revision—not unrelated SwiftUI updates.

## 4. Sequential implementation gates

### Gate 0 — Contract and registry consistency

Add typed capability/renderer contracts, a format manifest/consistency check, and the generation/cancellation contract. Compare registry extensions/UTTypes, `project.yml`/Info.plist declarations, highlight IDs, preview capabilities, and CLI format behavior. No implementation slice proceeds with drift.

### Gate 1 — JSON core

Create a Foundation-only JSON support target or clearly isolated FileCore module containing diagnostics, parsing, deterministic formatting, and outline building. Do not route JSON through Markdown parsing. Pass diagnostics, formatting, outline identity/source-range, cancellation, and Release performance tests before UI wiring.

### Gate 2 — JSON editor/workspace integration

Add Format JSON and Format JSON with sorted keys commands. Route formatting through the existing editor replacement/undo/binding/recovery path. Add stale generation, external replacement, one-undo, one-publication, selection, and format-transition tests. Commands must be disabled for non-JSON/invalid states.

### Gate 3 — Format-neutral outline and preview integration

Preserve Markdown outline behavior while adding JSON adapters. Add per-tab preview mode state, session migration only if persistence is required, Save As format invalidation, layout-mode interaction, accessibility identifiers, and no-stale-Markdown-state tests.

### Gate 4 — HTML source/rendered preview

Implement the approved security policy, scoped base URL/resource loading, source/rendered toggle, save-triggered reload, cancellation, disposal, and navigation tests. Keep the WebKit host in its current owner unless a separate boundary change is approved.

### Gate 5 — Grammar completion

Add one grammar dependency at a time. Before declaring a language supported, prove exact pinned resolution, target/product names, C entry point, query resources, license/notice obligations, Release resource inclusion, and capture smoke tests. Unsupported or failed grammars remain explicit no-highlight states.

Suggested risk-based order: CSS/JavaScript/TypeScript; Python/Ruby/Bash/SQL; YAML/TOML/XML; Swift/C/C++. Do not add all packages in one unreviewable change.

### Gate 6 — Release and hosted acceptance

Require serial package tests in CI, Debug/Release app and CLI builds, generated Xcode project verification, targeted app/UI tests, Release performance results, dependency/license inventory, and (where available) TSan. No gate may weaken existing assertions or replace service/app proof with mocks.

## 5. Required test matrix

Name suites or equivalent coverage:

- `JSONDiagnosticsTests`
- `JSONFormattingTests`
- `JSONFormattingUndoPublicationTests`
- `JSONFormattingGenerationRaceTests`
- `JSONOutlineIdentityTests`
- `JSONOutlineSourceRangeTests`
- `JSONOutlinePerformanceTests`
- `PreviewCapabilityRoutingTests`
- `PreviewModeSessionTests`
- `HTMLPreviewSecurityTests`
- `HTMLPreviewResourceScopeTests`
- `HTMLPreviewReloadGenerationTests`
- `FormatTransitionTests`
- `FormatRegistryConsistencyTests`
- `GrammarRegistryCompletenessTests`
- `GrammarFailureIsolationTests`
- `GrammarDependencyResourceTests`
- `GrammarColdLoadPerformanceTests`
- `NoPreviewAccessibilityUITests`
- `JSONOutlineUITests`
- `HTMLToggleUITests`
- `SaveAsFormatTransitionUITests`

Minimum scenarios include:

- valid/invalid JSON, Unicode, CRLF, BOM, top-level scalar, duplicate keys;
- deterministic sorted formatting, one undo/publication, edit-during-format, external replacement, and generation mismatch;
- nested/duplicate/empty JSON nodes, 10,000-node and deep documents, source jumps, collapse/selection remapping, and invalid-input policy;
- HTML relative image/style/font/media, missing resources, traversal, symlink escape, untitled/moved documents, blocked navigation/network/script behavior, stale reload, disposal, and scope balance;
- every advertised extension, case normalization, UTType/project metadata, grammar query loading/failure, cache behavior, and no-preview fallback;
- Markdown↔JSON↔HTML Save As, tab isolation, session round-trip, stale parser/outline clearing, and Markdown-only editing assists.

## 6. Performance budgets and evidence

These are initial Release targets and must be confirmed against measured baselines, not treated as proof until the full app path is exercised:

- JSON validation: debounce ≤150 ms; 100 KB under 50 ms.
- JSON formatting: 100 KB under 100 ms; 1 MB under 500 ms.
- JSON outline: 10,000 nodes under 200 ms off the main actor.
- Grammar cache hit under 1 ms; cold load under 200 ms where practical.
- HTML: no more than one WebKit load per saved source revision; unrelated SwiftUI updates cause zero reloads.
- Record median and p95 separately for pure parser work and editor/UI publication at 100 KB, 1 MB, and 10 MB inputs.

## 7. Dependency and release evidence

Every new grammar or renderer dependency requires exact version/revision, license/notice, transitive dependency inventory, resource-bundle ownership, archive inclusion, known maintenance/security risk, and a reproducible package resolution. No unpinned range may remain in the final implementation PR.

## 8. Explicit deferrals

- JSON Schema validation;
- HTML source-editing assists;
- remote/network HTML preview;
- arbitrary JavaScript bridges or unrestricted local file access;
- full AST-aware formatting for every language;
- PDF/export changes;
- plugin-provided grammar discovery;
- settings/localization redesign.

## 9. Planning review record

This plan was checked independently from two angles:

- **Adversarial review:** identified P1 risks around formatting publication, HTML security/resource policy, grammar dependency buildability, and preview routing, plus P2/P3 gaps in diagnostics, outline identity, cancellation, performance, registry consistency, and dependency evidence.
- **Architecture implementation audit:** mapped each slice to current `FileCore`, `EditorCore`, `Preview`, `OutlineUI`, `Workspace`, `Highlighting`, `project.yml`, and package ownership, and identified issue-text conflicts with the as-built WebKit host, Markdown-specific outline/parser, and existing format registry.

The Epic is ready for implementation planning review, not yet for production implementation or merge of feature code.

