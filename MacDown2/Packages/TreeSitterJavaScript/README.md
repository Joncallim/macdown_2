# TreeSitterJavaScript (vendored)

JavaScript grammar used for editor syntax highlighting. It is vendored because
no upstream tag has a `Package.swift` that lists its sources explicitly
(`planning/epic-11-implementation.md` §7).

## Provenance

| | |
|---|---|
| Upstream | https://github.com/tree-sitter/tree-sitter-javascript |
| Release | `v0.25.0` |
| Commit | `44c892e0be055ac465d5eeddae6d3e194424e7de` |
| Licence | MIT, Copyright (c) 2014 Max Brunsfeld (`LICENSE`, identical to upstream) |
| Verified | 2026-09-28, by comparing the Git blob hash of every vendored file with the upstream history |

`src/parser.c`, `src/scanner.c`, `src/tree_sitter/*.h` and all six query files
are byte-identical to upstream `v0.25.0`. There are no local modifications.
`Package.swift` and `TreeSitterJavaScriptResources.swift` are first-party.
