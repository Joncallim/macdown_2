#!/bin/bash
# Reproduces Problem A (see ../../../../h5-dependency-followup.md). Usage:
#   run_A.sh <tree-sitter checkout at TS_REVISION> <MacDown2/Packages/TreeSitterMarkdown> <workdir>
# e.g. run_A.sh MacDown2/Packages/MacDownKit/.build/checkouts/tree-sitter MacDown2/Packages/TreeSitterMarkdown /tmp/repoA
# Builds three C binaries from the same sources: stock, +goto counters, +binary-search ts_lexer_goto.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TS=$(cd "$1" && pwd); GR=$(cd "$2" && pwd); W=$3
mkdir -p "$W"; cd "$W"
[ "$(git -C "$TS" rev-parse HEAD)" = "$(cat "$HERE/../TS_REVISION")" ] || echo "WARNING: tree-sitter is not at $(cat "$HERE/../TS_REVISION")" >&2
for v in stock instr bsearch; do rm -rf "ts-$v"; mkdir "ts-$v"; cp -R "$TS/lib" "ts-$v/lib"; done
patch -s -p0 "ts-instr/lib/src/lexer.c" < <(sed 's#^--- .*#--- lexer.c#; s#^+++ .*#+++ lexer.c#' "$HERE/ts_lexer_goto_counters.diff")
patch -s -p0 "ts-bsearch/lib/src/lexer.c" < <(sed 's#^--- .*#--- lexer.c#; s#^+++ .*#+++ lexer.c#' "$HERE/ts_lexer_goto_bsearch.diff")
IN="$GR/Sources/TreeSitterMarkdownInline/src"
for v in stock instr bsearch; do
  extra=""; [ $v = instr ] && extra="-DCOUNT"
  cc -O2 $extra -I "ts-$v/lib/include" -I "ts-$v/lib/src" -I "$IN" "$HERE/harness.c" "ts-$v/lib/src/lib.c" "$IN/parser.c" "$IN/scanner.c" -o "h_$v"
done
# N = number of included ranges; 262144 bytes of inline content; 9 runs (p50/p95 over them).
for v in stock instr bsearch; do echo "== $v"; ./h_$v 262144 9 10 100 1000 3000 10000 30000; done
