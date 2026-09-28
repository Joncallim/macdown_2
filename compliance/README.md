# Third-party licence and provenance gate

**Owner summary.** MostlyText ships under MIT, but it also ships about 30
third-party components: parsers, a Markdown library, diagram engines compiled
to JavaScript and WebAssembly, math fonts, and colour themes. Each keeps its
own licence, and some licences (Graphviz's EPL-2.0, D2's MPL-2.0) also require
the source to be available. This directory is the release gate for those
obligations (#148, LC-01 to LC-09):

- `inventory.json` lists every third-party component the app ships, where it
  came from (exact upstream revision), its licence and the files it owns.
- `tools/compliance.py` checks that list against the source tree, generates
  the notices file and a software bill of materials (SBOM), and, at release
  time, refuses to pass while anything is pending or unverified.
- `generated/` holds the generated `THIRD_PARTY_NOTICES.md` and
  `sbom.cdx.json`. The About → Open Source Licences screen (LC-08) will show
  the notices file, so no one maintains a second hand-written copy.

Why this way: the notices have to match what actually ships, byte for byte.
A single machine-checked inventory catches a new library, a changed file or a
deleted licence text in CI, instead of in a manual audit before release.

Risks and limits: this is evidence gathering, not legal advice, and no legal
clearance is claimed. Three things can't be proved from this repository
alone: the exact SwiftPM revisions (they come from the LC-05 lock file, which
another task owns), the contents of the final signed app (checked on a Mac
with `--artifact`), and public source availability (checked when LC-09 hosting
exists). Those stay **unverified**, never passed, until they are checked.

Non-goals: this doesn't change the app, its dependencies or the lock file,
and it doesn't publish anything.

## Commands

Run from the repository root. They need only Python 3.11 or later.

| Task | Command |
|---|---|
| Check the inventory against the tree | `python3 compliance/tools/compliance.py check` |
| Show everything still blocking public 1.0 | `python3 compliance/tools/compliance.py check --release` |
| Check a built app or mounted DMG (Mac) | `python3 compliance/tools/compliance.py check --release --artifact /path/MostlyText.app` |
| Regenerate the notices file | `python3 compliance/tools/compliance.py notices` |
| Regenerate the SBOM | `python3 compliance/tools/compliance.py sbom` |
| Run the tool's own tests | `python3 -m unittest discover -s compliance/tests` |

The `Compliance` workflow runs the tests and the tree check on any change to
this directory, bundled resources, vendored packages, manifests or lock files.
It also prints the release ledger for information; that step is expected to
fail until the release candidate exists.

## What the check rejects

| Rule | Tree check | `--release` |
|---|---|---|
| A file under `MacDown2/` that is neither first-party nor owned by a component | fail | fail |
| A SwiftPM dependency or local package not in the inventory | fail | fail |
| A manifest requirement that differs from the inventory (stale mapping) | fail | fail |
| A missing or edited licence/notice text, or a vendored file whose digest changed | fail | fail |
| A copyleft component with no source location recorded | fail | fail |
| Generated notices or SBOM out of date with the inventory | fail | fail |
| No lock file, an unregistered resolved package, or a resolved revision that differs from the inventory | unverified until `lockfile_enforced` is `true` | fail |
| A component still `pending`, or with open items | allowed | fail |
| A source location not yet verified by anonymous download | allowed | fail |
| With `--artifact`: a bundled engine or the notices file missing from the app | — | fail |

The tests in `tests/test_compliance.py` break a passing fixture one way at a
time (unregistered component, deleted notice, wrong digest, stale lock-file
and manifest mapping, missing source location) and assert each fails.

## When you change a dependency or bundled file

1. Update the component in `inventory.json`: version, full revision, digests,
   and the licence texts. Take licence texts verbatim from the upstream
   revision and put them in `licenses/` as `<component-id>--<FILE>.txt`,
   recording the upstream path, revision and SHA-256.
2. Run `notices` and `sbom`, then `check`.
3. Commit the inventory, the licence texts and `generated/` together.

**After the LC-05 lock file lands:** update each `pending-lockfile` component
to the locked revision, re-check its licence text at that revision, register
any additional resolved packages, and then set `"lockfile_enforced": true`.
From then on a lock-file change that isn't reflected here fails CI.

## Provenance findings (2026-09-28)

Method: compare the Git blob hash or SHA-256 of each shipped file with the
upstream history or the published npm tarball. Nothing below was inferred from
file names or comments alone.

| Item | LC | Finding |
|---|---|---|
| TreeSitterMarkdown (vendored) | LC-04 | Every parser, scanner, header and injection-query file is byte-identical to `tree-sitter-grammars/tree-sitter-markdown` **v0.5.3** (`f969cd3`). MIT, © 2021 Matthias Deiml. The package had no licence file: `LICENSE` is now copied verbatim from that tag, and `README.md` records the evidence. The two `highlights.scm` files are local rewrites for this app's capture names. Upstream says those queries came from nvim-treesitter, so its Apache-2.0 notice is carried as well, conservatively. |
| TreeSitterJavaScript (vendored) | LC-01 | Byte-identical to `tree-sitter-javascript` **v0.25.0** (`44c892e`). No local changes. |
| TreeSitterSQL (vendored) | LC-01 | Byte-identical to upstream's generated-source deploy `851e9cb` (`gh-pages`), built from `main` `3c99273` (after v0.3.11). No local changes. The package README that `Package.swift` referred to didn't exist; it does now. |
| Tomorrow Dark theme | LC-06 | Chris Kempson's Tomorrow **Night Eighties** palette (MIT), by way of MacDown's legacy `Tomorrow.style` (MIT), including MacDown's `#888888` comment colour. Attribution added for both. |
| "Tomorrow Light" theme | LC-06 | **Not derived from Tomorrow.** Its seven token colours all come from GitHub's `github-syntax-light` v0.4.1 palette (MIT, © 2016 GitHub, Inc.); the text, caret and selection colours are local choices. The licence is fine and attribution is added. The misleading name belongs to E23 (#113), which owns theme integration and will decide whether to rename or re-source the theme. |
| Mermaid, Viz.js | LC-01, LC-02 | `mermaid.min.js` and `viz-global.js` are byte-identical to the npm releases mermaid@11.17.2 and @viz-js/viz@3.30.0. The viz bundle reports Graphviz 16.0.0. |
| D2 | LC-03 | Identical to npm @terrastruct/d2@0.1.33 except the one documented export statement. The existing `NOTICE.txt` is accurate. |
| SwiftUIMath fonts | LC-01 | New finding: SwiftUIMath ships 12 OpenType math fonts under the SIL Open Font License 1.1 and the GUST Font License. Their licence texts and each font's own copyright line (read from its `name` table) are now in the notices. |
| libyaml in Yams | LC-01 | New finding: Yams ships libyaml's C sources without libyaml's licence file. The libyaml MIT notice is added. |

Open items per component are listed in `inventory.json` and by
`check --release`. The main ones: exact SwiftPM revisions (waiting on LC-05),
Mermaid's bundled npm dependencies, the Graphviz and D2 corresponding-source
packages (LC-02, LC-03 and LC-09), and confirming the font set in the signed
app.
