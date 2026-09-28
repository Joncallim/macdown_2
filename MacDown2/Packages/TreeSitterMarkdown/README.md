# TreeSitterMarkdown (vendored)

Block and inline Markdown grammars used for editor syntax highlighting.

## Provenance

| | |
|---|---|
| Upstream | https://github.com/tree-sitter-grammars/tree-sitter-markdown |
| Release | `v0.5.3` |
| Commit | `f969cd3ae3f9fbd4e43205431d0ae286014c05b5` |
| Licence | MIT, Copyright (c) 2021 Matthias Deiml (`LICENSE`, copied verbatim from that commit) |
| Verified | 2026-09-28, by comparing the Git blob hash of every vendored file with the upstream history |

Every parser, scanner, header and injection-query file is byte-identical to
the upstream file at `v0.5.3`:

| Vendored file | Upstream file |
|---|---|
| `Sources/TreeSitterMarkdown/src/parser.c`, `scanner.c`, `tree_sitter/*.h` | `tree-sitter-markdown/src/…` |
| `Sources/TreeSitterMarkdownInline/src/parser.c`, `scanner.c`, `tree_sitter/*.h` | `tree-sitter-markdown-inline/src/…` |
| `Sources/TreeSitterMarkdownResources/queries/injections.scm` | `tree-sitter-markdown/queries/injections.scm` |
| `Sources/TreeSitterMarkdownInlineResources/queries/injections.scm` | `tree-sitter-markdown-inline/queries/injections.scm` |

The generated `parser.c` files declare tree-sitter `LANGUAGE_VERSION 15`.

## Local modifications

Only the two `highlights.scm` query files differ from upstream. They were
rewritten to emit this app's canonical capture names (for example
`@text.title` became `@markup.heading`, `@text.literal` became `@markup.raw`
and `@punctuation.special` became `@punctuation`). Two pattern changes go with
the renaming: heading captures cover the whole `atx_heading`/`setext_heading`
node rather than only its inline text, and the separate heading-marker and
emphasis/code-span delimiter captures were removed. Run `diff` against the
upstream files for the exact change.

Upstream marks both query files as originating in
[nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter)
(Apache-2.0) and redistributes them under its own MIT licence. The release
notices include the nvim-treesitter Apache-2.0 notice as well, as a
conservative attribution.

The Swift wrapper files (`*Resources.swift`) and `Package.swift` are
first-party.

## Updating

Replace the files from a single upstream release tag, re-run the blob-hash
comparison, and update this table and `compliance/inventory.json` in the same
change. `python3 compliance/tools/compliance.py check` fails if the recorded
digests and the vendored bytes disagree.
