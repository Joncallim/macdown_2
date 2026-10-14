# Mermaid 11.17.2 nested-bundle audit

Audit date: 2026-10-14. This is provenance evidence, not legal clearance.

## Verified local evidence

- Vendored file: `MacDown2/Packages/MacDownKit/Sources/DiagramRendering/Resources/mermaid.min.js`
- Recorded and recomputed SHA-256: `581ed7d74bd9048d0e3a91363927d72ef22942d7722546b27f7cc29e35390eb8`
- Recorded package: `mermaid@11.17.2`
- Existing inventory evidence says the hash equals `dist/mermaid.min.js`
  from the `mermaid@11.17.2` npm tarball.
- Existing inventory records the top-level `nested` dependency ranges below.

The local checkout does not contain Mermaid’s v11.17.2 release lockfile,
resolved package tarballs, or the nested package license texts. A top-level
`package.json` range is not treated as proof of the version bundled into the
single-file artifact.

## Declared nested inputs requiring lockfile resolution

| Package | Declared range | Exact bundled version | License text |
|---|---|---|---|
| `@braintree/sanitize-url` | `^7.1.2` | pending lockfile | pending source package |
| `@iconify/utils` | `^3.0.2` | pending lockfile | pending source package |
| `@mermaid-js/parser` | `^1.2.1` | pending lockfile | pending source package |
| `@upsetjs/venn.js` | `^2.0.0` | pending lockfile | pending source package |
| `cytoscape` | `^3.34.0` | pending lockfile | pending source package |
| `cytoscape-cose-bilkent` | `^4.1.0` | pending lockfile | pending source package |
| `cytoscape-fcose` | `^2.2.0` | pending lockfile | pending source package |
| `d3` | `^7.9.0` | pending lockfile | pending source package |
| `d3-sankey` | `^0.12.3` | pending lockfile | pending source package |
| `dagre-d3-es` | `7.0.14` | pending lockfile | pending source package |
| `dayjs` | `^1.11.21` | pending lockfile | pending source package |
| `dompurify` | `^3.3.3` | pending lockfile | pending source package |
| `es-toolkit` | `^1.45.1` | pending lockfile | pending source package |
| `fastdom` | `1.0.12` | pending lockfile | pending source package |
| `katex` | `^0.16.47` | pending lockfile | pending source package |
| `khroma` | `^2.1.0` | pending lockfile | pending source package |
| `marked` | `^16.3.0` | pending lockfile | pending source package |
| `roughjs` | `^4.6.6` | pending lockfile | pending source package |
| `stylis` | `^4.3.6` | pending lockfile | pending source package |
| `ts-dedent` | `^2.2.0` | pending lockfile | pending source package |
| `uuid` | `^11.1.0 \|\| ^12 \|\| ^13 \|\| ^14.0.0` | pending lockfile | pending source package |

## Smallest reproducible completion step

1. Obtain the official Mermaid v11.17.2 release source and its lockfile
   (`pnpm-lock.yaml` or the release’s equivalent) without modifying the
   vendored runtime file.
2. Resolve the 20 names above from that lockfile, including transitive
   packages actually included in the generated `dist/mermaid.min.js`.
3. For every resolved package, record package name, exact version, source
   revision/tarball hash, SPDX/licence expression, and the verbatim official
   licence/notice file in `compliance/licenses/`.
4. Recompute the vendored bundle hash and record the lockfile/source evidence
   alongside the inventory entry. A mismatch stops the audit.

Until those inputs are available, the exact nested versions and required
notice texts are not established. No source package or notice was fabricated
by this tranche.
