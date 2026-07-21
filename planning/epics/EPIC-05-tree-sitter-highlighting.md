> **Title:** [EPIC-05] Tree-sitter highlighting engine + theme system
> **Labels:** `epic`, `editor` · **Milestone:** M2 — Editor · **Depends on:** E04

## Context

Editor highlighting replaces peg-markdown-highlight (C/PEG, unmaintained) with
tree-sitter via SwiftTreeSitter (MIT): incremental re-parse on each edit —
O(edit), not O(document). This is how we hit "< 50 ms keystroke → highlight".

## Scope

- `Highlighting` target: SwiftTreeSitter integration; highlight session per
  open tab; async attribute application into TextKit 2 storage (no main-thread parse)
- Grammar registry + build: ship **markdown, markdown-inline, json, html, css,
  javascript, typescript, python, yaml, toml, swift, bash, sql, xml, ruby,
  c, cpp** (start: markdown + json + html; registry makes the rest additive)
- Language resolution from `FileFormat` registry (E01)
- Theme engine: port MacDown editor themes (`.styles`/CSS in `MacDown/Resources`)
  to a Swift theme model (decision O4: pick which ship); light/dark variants;
  live theme switching
- Graceful degradation: unknown language → plain text, never an error state

## Deliverables

1. Highlighting engine + at minimum markdown/json/html grammars working
2. Theme model + 2 ported themes (one light, one dark) to validate the model
3. Perf tests: keystroke → highlight < 50 ms on 1 MB doc; full highlight of
   1 MB < 500 ms on open

## Acceptance criteria

- [ ] Editing inside a fenced code block re-highlights only the affected range (instrumented)
- [ ] Switching theme recolors instantly without reparse
- [ ] Opening a file of every registered format either highlights or cleanly no-ops
- [ ] Port of relevant `MPColorTests` (hex/named colors in themes) passes in Swift
- [ ] Zero main-thread parse time > 8 ms on a 1 MB doc (XCTMetric)

## Out of scope

Preview-side highlighting (Textual handles MD code blocks; E07). Editing
assists (E10).

## Notes

Grammar build friction is the risk: isolate each grammar in its own SPM target
or xcframework so a broken grammar never blocks the app build.
