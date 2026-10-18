# Release preparation ledger (#148)

This is an evidence-preparation record, not a release approval or legal
clearance. It is intentionally kept on the integration branch so the release
owner can review the remaining work. The 2026-10-18 font reconciliation records
an existing product decision; it does not publish source archives, sign artifacts,
accept agreements or verify the remaining source offers.

## Reconciled checks

Run from the repository root on 2026-10-14:

```text
python3 compliance/tools/compliance.py check
compliance check (tree): passed, 0 unverified item(s)
```

The historical 2026-10-14 release check reported eight raw inventory entries.
On 2026-10-18, the recorded KEEP-all-12 font decision was reconciled in inventory;
the current release check remains blocked by seven entries. No provenance or
source-offer `status` field changed. See the
[font reconciliation evidence](evidence/swiftui-math-fonts-2026-10-18/README.md).

| Component | Current blocker | Material prepared or still required |
| --- | --- | --- |
| `d2` — source-location verification | Planned source URL; anonymous retrieval not verified | Existing `ARCHIVE_PLAN.md` identifies the upstream package and archive evidence still required. Do not publish or mark verified here. |
| `d2` — `LC-03` | Go revision/module provenance open | Identify the D2 Go revision/modules, licences, upstream package and one-line patch. |
| `mermaid` — nested-bundle item | Complete nested attribution and distributed texts unresolved | The [generated-bundle audit](evidence/mermaid-11.17.2/README.md) now links the exact artifact, parser and mapped modules to captured licence texts. Resolve the remaining prebundle attributions/candidate-version limits before installing the complete inventory/notices/SBOM. |
| `theme-tomorrow-light` — E23 item | Naming/source decision | Existing provenance says the palette is GitHub-derived, not Tomorrow-derived; E23 must decide whether to rename or re-source it. |
| `viz-js` — source-location verification | Planned source URL; anonymous retrieval not verified | Existing `ARCHIVE_PLAN.md` identifies the exact Graphviz/viz-js material and digest evidence still required. |
| `viz-js` — `LC-02` | Graphviz/viz-js source package and build-script pinning open | Pin exact Graphviz 16.0.0 and viz-js 3.30.0 source/build material and hashes. |
| `viz-js` — linked-library review | Linked-library obligations open | Confirm whether the WebAssembly build links libraries such as expat and add notices if required. |

The checker reports these seven exact entries. SwiftUIMath's product-decision
entry is resolved using the recorded KEEP decision in issue #148 comments
5868785863 and 5867001043. All 12 font resources, digests, licence texts and
artifact requirements remain. Notices and SBOM regenerate byte-identically.
The unsigned local artifact check is not the final signed-artifact check, and
this reconciliation is not evidence that any source offer is publicly reachable.

The retained unsigned Release app additionally **fails three artifact checks**:
it lacks the byte-identical repository `LICENSE` and generated notices, and ships
an unregistered `textual_Textual.bundle/Contents/Resources/prism-bundle.js`.
Those same failures occur against the baseline and reconciled inventory. The
source-only seven-item ledger is not the full artifact ledger; release checking
with this artifact reports ten findings. All 12 font digests are present, which
does not waive the missing notices or any other distribution obligation.

The script bytes match the clean, locked Textual checkout. Its bundler declares
Prism 1.29.0, but that observation is not a complete embedded-code/licence audit.
Review the bundled source and obligations before adding its inventory/notices;
do not simply allowlist the digest. Bundling `LICENSE` and generated notices is
already specified in `LICENCES_UI.md`, whose app integration remains incomplete.

## Corresponding-source preparation boundary

`ARCHIVE_PLAN.md` is the authoritative preparation plan. The repository has
not created public archives, changed source-offer URLs, generated a release
archive, signed an artifact, or claimed anonymous retrieval. The remaining
safe preparation steps are source/archive assembly and digest review only:

1. identify the exact D2 Go source revision and module licences;
2. identify the Graphviz/viz-js source and any linked-library obligations;
3. complete Mermaid's remaining prebundle attribution and notice gaps from the
   generated-artifact evidence, rather than equating lock resolution with inclusion;
4. obtain the E23 Tomorrow Light naming decision and retain the font requirements
   through final-artifact verification.

Only after an owner-authorized source-only publication may the URLs and
`source_offer.status` values be updated and the release candidate checked.
