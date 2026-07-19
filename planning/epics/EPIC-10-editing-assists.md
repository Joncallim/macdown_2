> **Title:** [EPIC-10] Editing assists: list continuation, auto-pairing, indenting
> **Labels:** `epic`, `editor` · **Milestone:** M2 — Editor · **Depends on:** E04

## Context

Ports the beloved behaviors from `NSTextView+Autocomplete` (ObjC category) into
the new editor. These make MacDown feel like a Markdown editor rather than a
plain text field; correctness here is very testable.

## Scope

- Return-key continuations: unordered/ordered lists (with auto-increment),
  task lists, blockquotes; empty item + Return exits the construct
- Auto-pairing: `*`, `_`, `` ` ``, `**`, brackets/quotes; type-over closing char;
  wrap-selection on typing a pair char with text selected
- Indent/unindent with Tab/⇧Tab (spaces, pref-driven width); smart Home key
  (first non-whitespace ↔ column 0 toggle)
- Header toggle (⌘1–6 via markup toggle), bold/italic/code shortcuts
  (⌘B/⌘I/⌘E — final set decided against menu conflicts)
- All assists Markdown-only (disabled in JSON/HTML/etc. to avoid fights with
  those languages' pairing)

## Deliverables

1. Assist engine in `EditorCore` operating on the text storage pre-edit
2. Unit tests for every behavior above (direct ports of the ObjC semantics,
   extended where tests reveal bugs)
3. XCUITest smoke: typing a list produces continued items

## Acceptance criteria

- [ ] Each ObjC behavior from `NSTextView+Autocomplete` either ported or
      explicitly documented as dropped
- [ ] Assists never fire in non-Markdown formats
- [ ] All assists undo as a single undo group
- [ ] No measurable keystroke latency regression (< 50 ms budget holds)

## Out of scope

Autocomplete of links/images, snippet system (v1.x).

## Notes

This is the "feel" epic — pair with real-Markdown dogfooding before calling
M2 done.
