# Correct parser byte columns without changing highlighting policy

## Owner summary

The app currently tells its pinned syntax parser that a position is half as far
along a line as the parser's UTF-16 input actually places it. This bounded
correction will make editor offsets and parser coordinates agree. It does not
change which documents receive highlighting, adopt experimental dependencies,
or claim to fix the unexplained hosted restored-style mismatch.

## Baseline and contract

Inspected candidate: `2c69411c1ae0fb727a211139fc19ceedad1fd4de`, tree
`ab26dd779024d2b99d8223e2bfe14b4be36142be`. Live local master remains
`4aa46bfa6b91bf1c1d218b9b1f67480312f66396`. The production package lock is
unchanged, SHA-256
`9c7c1835b89d1248bd156e1caa45c7691098b36ef1aabea35a8974b5c15f8977`.
This is the byte-coordinate slice of #459 / PR #462, reconciled to current
integration. PR #462's larger lifecycle and dependency proposals remain separate.

AppKit offsets count UTF-16 code units. A tree-sitter Point has a zero-based row
and a byte column. The pinned SwiftTreeSitter parser reads UTF-16, so each code
unit occupies two input bytes, including each half of a surrogate pair. The
pinned Neon adapter converts edit offsets to bytes but forwards the host's
Points unchanged. The host currently returns code-unit columns. Existing
location unit tests mirror that error, while direct parser tests already use
byte columns. Line boundaries remain LF; CRLF contributes its CR to the prior
line without creating a second row.

## Bounded implementation and evidence order

1. Before production edits, mount a real EditorTextSystem in an AppKit window
   with pinned TextViewHighlighter. Wrap the actual host transformer only to
   record the offsets and Points the adapter requests. Perform a same-line JSON
   insertion through `insertText`, including a non-ASCII prefix case. Derive
   expected old/new number-node endpoints from independently parsed old/new
   strings. Require actual adapter calls and compare their returned Points.
2. Preserve the failing baseline. A fresh parse/style equality alone is not a
   discriminator: reparsing can conceal incorrect edit coordinates. Same-line
   insertions deliberately keep prefix geometry stable so the separate old/new
   snapshot problem does not confound this byte-unit test.
3. Correct only the host transformer's column unit, including its fallback, and
   update its explanation and directly affected expectations. Add parser-derived
   coordinate coverage for Unicode, CRLF and line boundaries. Keep revision-based
   line-cache invalidation and offset clamping.
4. Run the focused mounted regression and existing coordinate tests in Debug
   and Release, then the relevant highlighting correctness/performance suites.
   Retain first failures. Independent review must verify the actual patch and
   source-matched results before publication through existing PR #493.

No new module dependency, persistence behavior, permission model or package edit
is needed. The 8,192/6,144 UTF-16 fallback/restore thresholds and two-second idle
delay remain. No deadline or performance threshold is relaxed.

## Limits and stop conditions

The mounted harness exercises real TextKit 2, pinned Neon and the production
transformer; it does not execute an IME or the complete application journey.
Native Pinyin coverage remains limited to its recorded manual cases. This slice
does not close #459, #183, #203 or #88.

Post-await snapshot validation, stale style delivery, old/new edit geometry,
highlighter/editor eviction order, dependency replacement, and parser latency
need their own discriminating evidence. Stop this slice if the byte correction
requires changing one of those contracts, weakening an assertion, or silently
reclassifying an existing failure. Historical hosted failures remain unresolved
unless their cause is independently demonstrated.

## Implemented correction and local checkpoint

The mounted baseline failed before the production edit: both old/new endpoint
comparisons failed for ASCII and Unicode-prefix insertions, and all three
parser-node coordinate vectors failed. Window attachment, TextKit 2 presence,
visible bounds, observed adapter calls, exact edited text and fresh-parser number
range controls passed. This establishes the byte-unit mismatch at the mounted
adapter, without attributing a historical style failure to it.

Both host return paths now express columns in UTF-16 bytes. Two existing unit
expectations that encoded code-unit columns are corrected. Independent source
review accepted the bounded patch. Review also found that the new fixture needed
the existing store eviction path to remove its undo observers and break the
layout graph; teardown now releases the highlighter and evicts its owned editor
before closing the window. This is fixture cleanup, not a claim of joined Neon
background work. Window creation was extracted without behavior changes to
satisfy the existing lint limit. Neither change alters the failing oracle.

The focused location tests, including the mounted regression, subsequently
passed in Debug and Release with forced dependency resolution and serial test
execution. The [retained logs and source hashes](evidence/highlighting-byte-columns-2026-10-19/)
distinguish the initial failing fixture from the reviewed passing source.
Repository log copies display literal carriage returns as `\r`; byte-exact
originals remain in the external archive. The manifest records both hashes and
this display-only transformation, preserving the CRLF fixture evidence.
Broader exact-commit validation is pending at this documentation checkpoint;
subsequent results must name their tested commit/tree. The external archive is
`/Users/jonathanlim/GitHub/_cleanup-archive/hosted-cleanup-2c69411c-2026-10-19/`.
No issue, native journey or release gate is closed by this checkpoint.
