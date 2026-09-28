# TreeSitterSQL (vendored)

SQL grammar used for editor syntax highlighting. It is vendored because
`DerekStride/tree-sitter-sql` never commits its generated `parser.c` to its
source branches or tags, so SwiftPM cannot build it from a release.

## Provenance

| | |
|---|---|
| Upstream | https://github.com/DerekStride/tree-sitter-sql |
| Generated-source commit | `851e9cb257ba7c66cc8c14214a31c44d2f1e954e` on upstream's `gh-pages` branch (deploy of the commit below) |
| Grammar source commit | `3c99273f9b32a00e38a737e8a0dd37397f931916` on `main` (2026-02-22; `git describe`: `v0.3.11-55-g3c99273`) |
| Licence | MIT, Copyright (c) 2021 Derek Stride (`LICENSE`, identical to upstream) |
| Verified | 2026-09-28, by comparing the Git blob hash of every vendored file with the upstream history |

`src/parser.c` (about 41 MB), `src/scanner.c`, `src/tree_sitter/*.h`,
`queries/highlights.scm` and `queries/indents.scm` are byte-identical to the
generated-source commit. That commit is upstream's own CI deploy of
`3c99273`, so the grammar source that produced `parser.c` is public at that
revision. There are no local modifications. `Package.swift` and
`TreeSitterSQLResources.swift` are first-party.

The source commit is not a release tag. Moving to a tagged release is optional
and not a compliance requirement; if it happens, regenerate this record and
`compliance/inventory.json` in the same change.
