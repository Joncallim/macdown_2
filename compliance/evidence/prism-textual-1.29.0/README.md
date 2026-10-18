# Bundle licence resources and account for Textual's Prism payload (#148)

## Owner outcome and scope

The unsigned app should contain the repository MIT licence and current generated
third-party notices, and its already-shipped Prism resource should have exact
provenance and attribution. This bounded change adds two build-resource references
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
Candidate and artifact review follow implementation.

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
