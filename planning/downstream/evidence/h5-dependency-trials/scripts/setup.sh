#!/bin/bash
# stage2/setup.sh: builds four dependency variants and four MacDownKit scratch copies.
#   deps/<v>/{SwiftTreeSitter,tree-sitter}  - plain source copies (directory names match the
#        SwiftPM identities `swifttreesitter` / `tree-sitter`, so the root path dependency
#        overrides Neon's transitive URL dependency on SwiftTreeSitter)
#   pkg/<v>/{MacDownKit,TreeSitter*}         - rsync of dep-trial MacDown2/Packages (no .build)
# Variant = (SwiftTreeSitter commit, tree-sitter commit):
#   stock = cbe31cb + da6fe9be (0.25.10)  A = cbe31cb + 091c0d7e
#   B     = dcdd946 (b-combined = B1+B2) + da6fe9be   AB = dcdd946 + 091c0d7e
set -euo pipefail
S=$(cd "$(dirname "$0")/.." && pwd); T=$S/stage2
REPO=/Users/jonathanlim/GitHub/macdown_2-deptrial
for v in stock A B AB; do
  case $v in stock) st=pinned; ts=pinned;; A) st=pinned; ts=a-lexer-goto-bsearch;; B) st=b-combined; ts=pinned;; AB) st=b-combined; ts=a-lexer-goto-bsearch;; esac
  D=$T/deps/$v; rm -rf "$D"; mkdir -p "$D/SwiftTreeSitter" "$D/tree-sitter"
  git -C $S/SwiftTreeSitter archive "$st" | tar -x -C "$D/SwiftTreeSitter"
  git -C $S/tree-sitter archive "$ts" Package.swift lib LICENSE | tar -x -C "$D/tree-sitter"
  # SwiftTreeSitter's own test grammar submodule (not in the archive)
  rm -rf "$D/SwiftTreeSitter/tree-sitter-swift"; cp -R "$S/vendor/tree-sitter-swift" "$D/SwiftTreeSitter/tree-sitter-swift"
  sed -i '' 's#\.package(url: "https://github.com/tree-sitter/tree-sitter", .upToNextMinor(from: "0.25.0"))#.package(name: "tree-sitter", path: "../tree-sitter")#' "$D/SwiftTreeSitter/Package.swift"
  grep -q 'path: "../tree-sitter"' "$D/SwiftTreeSitter/Package.swift"
  rm -f "$D/SwiftTreeSitter/Package.resolved"
  printf 'SwiftTreeSitter %s %s\ntree-sitter %s %s\n' "$st" "$(git -C $S/SwiftTreeSitter rev-parse $st)" "$ts" "$(git -C $S/tree-sitter rev-parse $ts)" > "$D/VARIANT"
  P=$T/pkg/$v; mkdir -p "$P"
  rsync -a --delete --exclude .build --exclude .swiftpm "$REPO/MacDown2/Packages/" "$P/"
done
