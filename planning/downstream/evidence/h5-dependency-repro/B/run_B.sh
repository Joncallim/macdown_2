#!/bin/bash
# Reproduces Problem B (see ../../../../h5-dependency-followup.md). Usage:
#   run_B.sh <SwiftTreeSitter checkout at SWIFTTREESITTER_REVISION> <MacDown2/Packages/TreeSitterMarkdown> <workdir>
# e.g. run_B.sh MacDown2/Packages/MacDownKit/.build/checkouts/SwiftTreeSitter MacDown2/Packages/TreeSitterMarkdown /tmp/repoB
# The scratch copy of SwiftTreeSitter gets swifttreesitter_scratch.diff: (1) Parser.includedRanges records the Bool from
# ts_parser_set_included_ranges; (2) the REPRO_B1 experiment in SwiftTreeSitterLayer's encorporateRanges (off unless set).
# Needs the tree-sitter C library: SwiftTreeSitter's own Package.swift resolves it from the network at its pinned revision.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ST=$(cd "$1" && pwd); GR=$(cd "$2" && pwd); W=$3
[ "$(git -C "$ST" rev-parse HEAD)" = "$(awk '{print $2}' "$HERE/SWIFTTREESITTER_REVISION")" ] || echo "WARNING: SwiftTreeSitter is not at the documented revision" >&2
mkdir -p "$W/vendor" "$W/B/Sources/Repro" "$W/B/Sources/TSMarkdown" "$W/B/Sources/TSMarkdownInline"
rm -rf "$W/vendor/SwiftTreeSitter"; cp -R "$ST" "$W/vendor/SwiftTreeSitter"
(cd "$W/vendor/SwiftTreeSitter/Sources" && patch -s -p0 < <(sed 's#^diff -ru a/\([^ ]*\) b/.*#diff \1#; s#^--- a/#--- #; s#^+++ b/#+++ #' "$HERE/swifttreesitter_scratch.diff"))
cp "$HERE/Package.swift" "$W/B/Package.swift"; cp "$HERE/main.swift" "$W/B/Sources/Repro/main.swift"; cp -R "$HERE/queries" "$W/B/Sources/Repro/queries"
for pair in "TreeSitterMarkdown:TSMarkdown:markdown.h" "TreeSitterMarkdownInline:TSMarkdownInline:markdown_inline.h"; do
  IFS=: read src dst hdr <<< "$pair"
  rm -rf "$W/B/Sources/$dst/src" "$W/B/Sources/$dst/include"; mkdir -p "$W/B/Sources/$dst/include"
  cp -R "$GR/Sources/$src/src" "$W/B/Sources/$dst/src"; cp "$HERE/include/$hdr" "$W/B/Sources/$dst/include/"
done
cd "$W/B" && swift build -c release 2>&1 | tail -3
echo "== stock (rejections are reported by the Repro output)"; ./.build/release/Repro
echo "== with the B1 experiment"; REPRO_B1=1 ./.build/release/Repro
