# React-derived KaTeX helpers in shipped Mermaid (#148 LC-01/07)

## Owner summary

The Mermaid bundle includes two KaTeX utility helpers that KaTeX expressly
credits to Facebook React under Apache 2.0. The previous MostlyText notices
carried KaTeX's MIT text but no notice for those borrowed helpers. This slice
adds Facebook's copyright and the full Apache 2.0 text as a separate,
conservative attribution. It does not resolve the other Mermaid nested-code
gaps or clear #148's release gate.

## Evidence and limit

The shipped `mermaid.min.js` SHA-256 is
`581ed7d74bd9048d0e3a91363927d72ef22942d7722546b27f7cc29e35390eb8`,
byte-identical to the integrity-checked official Mermaid 11.17.2 npm archive.
Its verified generated source map directly maps code to the exact official
KaTeX 0.16.47 `dist/katex.mjs` member (SHA-256
`09a78a9812d1e7d3ace85033512e6a450127b9554ef281b4b6567408694c6e36`).
Mapped generated positions reach the `hyphenate` line 12 times and the
`escape` line 15 times. [KaTeX's source](https://github.com/KaTeX/KaTeX)
contains the explicit React/Apache comment above them; it is present in the
official npm member as well.

[React v0.11.0](https://github.com/facebook/react/tree/95d82cacd6e9cc6a2fe6366d79510cc9133886cb)
is an immutable Apache-2.0-era reference. Its
[`hyphenate.js`](https://github.com/facebook/react/blob/95d82cacd6e9cc6a2fe6366d79510cc9133886cb/src/vendor/core/hyphenate.js)
and [`escapeTextForBrowser.js`](https://github.com/facebook/react/blob/95d82cacd6e9cc6a2fe6366d79510cc9133886cb/src/utils/escapeTextForBrowser.js)
have the matching transformation, character lookup and escape regex; both
credit Copyright 2013-2014 Facebook, Inc. and Apache 2.0. Its
[`LICENSE`](https://github.com/facebook/react/blob/95d82cacd6e9cc6a2fe6366d79510cc9133886cb/LICENSE)
is byte-identical to `compliance/licenses/react-katex--APACHE-2.0.txt`
(SHA-256 `c71d239df91726fc519c6eb72d318ec65820627232b2f796219e87dcf35d0ab4`).
The KaTeX comment does **not** name the original React revision, so v0.11.0 is
a matching licensed reference, not a claim of exact adaptation ancestry.
Later React revisions used a different licence; their text is not substituted
for this Apache-era attribution.

[`mapping.json`](mapping.json) records the hashes and mapped-line counts. The
new inventory record has kind `attribution`, not a claim that the complete
React package is bundled. Generated notices now include this separate text.
No application source or dependency pin changed.

## Replay and verification

The original Mermaid/KaTeX npm archives, registry metadata and the three
official React files are retained in
`/Users/jonathanlim/GitHub/_cleanup-archive/mermaid-148-40b25974-2026-10-18/`.
Run from the repository root:

```sh
python3 compliance/tools/audit_katex_react_attribution.py \
  --evidence-dir /Users/jonathanlim/GitHub/_cleanup-archive/mermaid-148-40b25974-2026-10-18 \
  --shipped MacDown2/Packages/MacDownKit/Sources/DiagramRendering/Resources/mermaid.min.js \
  --licence compliance/licenses/react-katex--APACHE-2.0.txt \
  --output /tmp/katex-react-mapping.json
cmp compliance/evidence/katex-react-attribution/mapping.json /tmp/katex-react-mapping.json
```

Three negative controls reject a changed shipped Mermaid bundle, modified
distributed React licence text and changed React helper source. Their output
is retained as `katex-react-negative-controls.log` in the raw evidence
directory. The full compliance suite, ordinary tree gate and generated-file
checks are run separately on the final committed head. The strict release
check still reports the same seven findings as the parent, including the
remaining Mermaid nested-attribution open item.

## Remaining work

Complete the documented Cytoscape borrowed-code, Rough.js prebundle,
candidate-version, KaTeX-adjacent and unmapped/generated-helper reviews in
`../mermaid-11.17.2/README.md`; update inventory and distributed texts only
for demonstrated content. Public source archives and exact signed-artifact
verification are later #148/E17 gates. Do not close #148 or mark Mermaid
attribution complete from this one borrowed-code notice.
