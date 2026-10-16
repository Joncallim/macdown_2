# Upstream candidate: binary search in `ts_lexer_goto` (patch A)

**Status: prepared, NOT submitted.** tree-sitter's contributing policy
(`docs/src/6-contributing.md`, "AI Policy") requires that a human is in the driver's seat,
forbids coding agents from interacting with the repository (including opening issues or PRs),
forbids copy-pasted LLM output in issue/PR text, and requires disclosure of any AI use.
This patch and these notes were produced with a coding agent, so an agent must not open the
issue or PR. Someone who understands the change should review it, reproduce it, write the
issue/PR text in their own words, and disclose the assistance. Searches of tree-sitter/tree-sitter
issues and PRs on 2026-10-16 (queries: "ts_lexer_goto included ranges", "included ranges lexer binary search",
"included_ranges slow", "set_included_ranges performance", "injection many ranges slow parse") found nothing existing.

## The change
`0001-perf-lib-binary-search-included-ranges-in-ts_lexer_g.patch` (14 insertions, 1 deletion in `lib/src/lexer.c`).
`ts_lexer_goto` scans the included-range list linearly from index 0 on every seek. The list is sorted and
non-overlapping (enforced by `ts_parser_set_included_ranges`), so end bytes are non-decreasing; the patch binary
searches for the first range ending after the position and keeps the existing forward skip over empty ranges.
Applies to tree-sitter `da6fe9be` (v0.25.10) and, checked from a local SwiftPM cache, to upstream master `8ca5488`
(which still has the linear scan).

## Evidence (what it does and does not show)
- Minimal reproduction: `planning/downstream/evidence/h5-dependency-repro/A/harness.c` and `run_A.sh` (C only; needs the
  `markdown_inline` grammar). Parses 262,144 bytes of inline text split into N included ranges, then reparses after
  a one-character edit (median of 9 runs): stock 137 / 175 / 492 / 1,122 / 4,739 ms at N = 10 / 1,000 / 10,000 /
  30,000 / 100,000; patched 136–153 ms at every N. `ts_lexer_goto` is called ~248k times regardless of N; loop iterations
  grow from 1.36 million (N=10) to 1.26 billion (N=10,000). `sample` at N=100,000: ~97% of samples in `ts_lexer_goto`.
  The ranges here are synthetic and evenly spaced.
- Correctness (stage 1, `planning/downstream/evidence/h5-dependency-trials/`): C test program output byte-identical to
  stock for markdown_inline, JSON and no-ranges cases; ASan/UBSan clean; identical tree hashes at N = 10 / 1k / 10k / 30k;
  upstream `make` builds with 0 warnings. Cases covered: empty, adjacent, EOF/past-EOF ranges, UTF-8 and UTF-16 with
  surrogates, edits at start/middle/end, delete-all, insert-at-EOF, 6,000 random edits.
- **Not run:** tree-sitter's Rust/corpus suite (crates and fixture grammars need network; not available here). There is
  no regression test for this patch in the upstream suite. A submitter should run `cargo xtask test` and add one.
- In a real application (MostlyText) with the patch, a one-character edit of a 256 KB Markdown document went from about
  500 ms to about 246 ms and a 1 MB layer edit from ~6.2 s to ~2.1 s. It is **not flat**: after the patch most of the
  remaining time is in `ts_parser__select_tree` / `ts_subtree_compare` and sublayer resolution, which is not
  investigated. The 1 MB inline-dense and long-lines benchmark cells are invalid measurements of the inline path and
  must not be quoted. Near 8 KB the patch gives nothing.
- This does not fix MostlyText's large-document stalls (register H5 / issue #203), and the description must not say so.

## Suggested disclosure (for the human to adapt)
"The investigation, patch and benchmarks were prepared with the help of a coding agent (Claude Code). I reviewed and
reproduced them myself on <date/machine>; this text is my own." Only write that if it is true.
