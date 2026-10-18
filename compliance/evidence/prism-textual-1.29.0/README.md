# Bundle licence resources and account for Textual's Prism payload (#148)

## Owner outcome and scope

The unsigned Release app now contains the repository MIT licence and current
generated third-party notices, and its already-shipped Prism resource has complete
byte-level provenance and preserved original attribution. This bounded change adds two build-resource references
and one audited resource component. It changes no renderer code, dependency,
editor behavior, folder permission or entitlement.

Baseline integration: `09e223bffd63c9b080592f566cfe6e2bbde4d8a7`.
Inspected local master: `4aa46bfa6b91bf1c1d218b9b1f67480312f66396`; its
`project.yml` matches the integration baseline. The existing
[LICENCES_UI contract](../../LICENCES_UI.md) already specifies copying these
original files through XcodeGen. This slice implements that packaging prerequisite,
not its unfinished About/Help window, localization or accessibility work.

## Exact shipped-resource audit

The retained unsigned Release app and the clean, locked Textual
`01b51875a5406eefc95f52a058cb059e7bc94dc4` checkout contain identical
138,163-byte `prism-bundle.js` files (SHA-256
`22b70192dc9d73377b5b8fe2c85655c7e3218afd37b65db638b4e168c4bacbf5`).
[The complete byte map](bundle-audit.json) accounts for:

- 122 bytes of Textual's generated header;
- the exact 18,997-byte cdnjs Prism 1.29.0 default distribution;
- 57 appended language-component files, each byte-identical to the Prism 1.29.0
  npm archive, in the shipped order;
- 58 newline separators and the exact 1,355-byte Textual helper heredoc.

No bytes remain unaccounted for. The audit compares actual artifact bytes; a
package list or lock file alone is not inclusion evidence.

The default payload includes core, markup, CSS, clike, JavaScript and file-highlight.
Those four default grammars also appear among the 57 appended component files.
The autoloader reference does not establish autoloader plugin inclusion. The
matching unminified CDN default is byte-identical to npm's default file.
Exact CDN matching establishes distribution provenance; minification was not
reproduced and the CDN source-map endpoint returned HTTP 404.

The npm archive's SHA-512 integrity and SHA-1 match published metadata. The
annotated v1.29.0 tag `8893d805d9a1287de497364079127c6eb26c97c6` resolves to
`59e5a3471377057de1f401ba38337aca27b80e03`, matching npm's gitHead.
Prism's tagged and npm MIT licence texts are byte-identical. Preserve its Lea Verou
copyright and full original text; preserve Textual's existing Guille Gonzalez MIT
text for the header/helper. No new terms or agreement are introduced.

Primary references: [Prism v1.29.0 licence](https://github.com/PrismJS/prism/blob/v1.29.0/LICENSE),
[npm 1.29.0 metadata](https://registry.npmjs.org/prismjs/1.29.0),
[default CDN bytes](https://cdnjs.cloudflare.com/ajax/libs/prism/1.29.0/prism.min.js).
The live cdnjs package record is corroboration only, not a historical build receipt.
Downloaded JavaScript and bundlers were never executed.

## Implementation contract and review

Use explicit app-target file references with `buildPhase: resources` for
`../LICENSE` and `../compliance/generated/THIRD_PARTY_NOTICES.md`. Regenerate
the Xcode project and use the existing pin-copy step. No new copy, generator
script, network build step or dependency is required.

Add an inventory `swiftpm-resource` for the actual Textual Prism bundle, with its
runtime digest, Prism and Textual licence records, precise version/provenance and
concatenation notes. Regenerate notices and SBOM through the existing generator.
Keep every existing component field and release finding. Do not modify the
checker to accept unknown bytes.

Independent read-only review accounted for all shipped bytes, identified the
default-bundle/plugin and annotated-tag distinctions, and accepted this bounded
packaging/inventory approach. It requires exact main-app resource paths in the
final artifact evidence, since the generic checker accepts known bytes anywhere.
The pre-commit candidate review found no material issue. The final artifact review
is recorded separately in [INDEPENDENT_REVIEW.md](INDEPENDENT_REVIEW.md).

## Validation and stop conditions

Retain the prior three-failure artifact output. On a committed candidate, run
source compliance from a clean archive, the unchanged compliance regressions,
deterministic generation checks, XcodeGen/pin verification, strict lint/format,
and one serial unsigned Release app build with first-party warnings-as-errors.
Check the generated Copy Bundle Resources entries and actual
`Contents/Resources/LICENSE` and `THIRD_PARTY_NOTICES.md` hashes. Verify the
new app's complete resource inventory, including all 12 fonts and exact Prism
bytes; release preflight must continue to report the seven independent source
findings. Record first failures rather than rerunning to obtain green.

A changed source/resource byte, new licence obligation, incomplete byte mapping,
pin change, unexplained build failure or new authority dependency stops dependent
work for diagnosis. The file-only preview workflow remains unimplemented pending
owner decision. #53/#203, original hosted failures, Pinyin coverage limits, native
release evidence, final signed-artifact verification and owner acceptance remain
open. No push, merge, signing, publication, issue closure or release is authorized.

Raw evidence:
`/Users/jonathanlim/GitHub/_cleanup-archive/prism-packaging-148-09e223bf-2026-10-18/`.

## Exact committed candidate and observed result

One finite validation pass ran on clean commit
`ceecea9c4a8297db6aa24e3afa9163406e4a10e5`, tree
`525887fedfb8bea2ffb1a7fa73978aae9353a482`, on CORTANA. Its source archive has
SHA-256 `ebdd2108342ff5d85ca850d5baffc4476ab5c20fbfbc241b541c69dbc1639df9`.
Commands, timestamps, log hashes and clean status after every command are in
[validation.json](validation.json). Later evidence/documentation commits do not
relabel that build as having run on a different head.

| Check | Observed result |
| --- | --- |
| Strict SwiftLint and SwiftFormat | Pass |
| Clean archived source compliance and existing compliance regressions | Pass |
| Generated notices and software bill of materials (SBOM) | Regenerate byte-identically |
| XcodeGen resource entries and locked dependency copies | Pass; both files are in the app Copy Bundle Resources phase |
| Serial Release app build, distribution signing disabled | Pass; 20:46:11–20:48:18 UTC on 2026-10-18 |
| Ordinary compliance against that actual app | Pass, including both exact main-app licence resource paths |
| Source and artifact release preflight | Both fail with the same seven unchanged findings; exit 1 retained |
| Runtime source, dependency pins, compliance checker and tests against baseline | Unchanged |

The build used macOS 26.5.1 (25F80), Xcode 26.6 (17F113), Swift 6.3.3 and
XcodeGen 2.46.0. Both architecture-specific app Swift compiler invocations used
Release optimization and `-warnings-as-errors`; this is not a warning-free build
claim. Xcode reported both a choice between matching arm64/x86_64 destinations
and skipped AppIntents metadata extraction. Those diagnostics and exact tool
outputs are retained in [build-inspection.json](build-inspection.json).
The resulting executable is universal x86_64/arm64. Its existing Release
configuration retains testability; this build does not exercise test targets.

The app is at `DerivedData/Build/Products/Release/MacDown2.app` under the raw
evidence directory. [artifact-files.json](artifact-files.json) records every one
of its 167 regular files and hashes; no symlinks were present. Key resources:

| App-relative path | Bytes | SHA-256 |
| --- | ---: | --- |
| `Contents/Resources/LICENSE` | 1,368 | `d6469c902a56daa3dd8f075486621f2e061d511d398d4a87f7e6dc84cb9f0d78` |
| `Contents/Resources/THIRD_PARTY_NOTICES.md` | 158,472 | `2e0f032cf971b0b5b9befae297e026941ecb241023b5f338ad081a9f6b1d8867` |
| `Contents/Resources/textual_Textual.bundle/Contents/Resources/prism-bundle.js` | 138,163 | `22b70192dc9d73377b5b8fe2c85655c7e3218afd37b65db638b4e168c4bacbf5` |

All 12 required math-font resource hashes match. Both dependency checkout pools
match all 22 production pins and are clean; see
[checkout-provenance.json](checkout-provenance.json). No experiment was adopted.

No signing command ran. The linker generated an ad hoc signature without a team
identity or sealed resources; `Info.plist` is not bound. This is unsigned evidence
for distribution purposes, not a signed release candidate. No performance, CLI,
app-test or native UI rerun was performed for this resource-only change. Earlier
failed measurements and hosted failures are preserved; they are not superseded
by a successful app build. The existing three-failure artifact record is also
unchanged: this is a newly built, corrected artifact, not a relabelled old result.

The reader can inspect the archived validation and audit scripts, captured
download metadata, file manifests and small check logs alongside this record.
`evidence-manifest.json` identifies retained raw files, including the full build
log, original npm archive and source archive. Static provenance does not prove
Prism runtime/network behavior, reproduced CDN minification or satisfaction of
other components' outstanding obligations.

The next step is owner review of this bounded correction while continuing the
seven remaining attribution/source/naming gates. The licence screen remains
unimplemented; #121's file-only asset workflow and OS-access decision remain
pending. #53, #203, native release coverage and owner acceptance remain open.

Before sealing, master remained clean at `4aa46bfa` and the dependency experiment
remained clean at `29e08843`. Process inspection found no heavy build or Claude
process rooted in the integration worktree. The two sleeping Claude CLI sessions
were rooted in the GitHub parent directory and the separate archived slice7a
checkout; neither was interrupted. The process/worktree snapshot is retained in
the raw evidence. All changes remain local; no remote state was changed.
