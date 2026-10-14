# Release preparation ledger (#148)

This is an evidence-preparation record, not a release approval or legal
clearance. It is intentionally kept on the integration branch so the release
owner can review the remaining work without changing inventory status,
publishing source archives, signing, or accepting agreements.

## Reconciled checks

Run from the repository root on 2026-10-14:

```text
python3 compliance/tools/compliance.py check
compliance check (tree): passed, 0 unverified item(s)
```

The release check remains blocked by eight raw inventory entries. No `status`
field was changed:

| Component | Current blocker | Material prepared or still required |
| --- | --- | --- |
| `d2` — source-location verification | Planned source URL; anonymous retrieval not verified | Existing `ARCHIVE_PLAN.md` identifies the upstream package and archive evidence still required. Do not publish or mark verified here. |
| `d2` — `LC-03` | Go revision/module provenance open | Identify the D2 Go revision/modules, licences, upstream package and one-line patch. |
| `mermaid` — nested-bundle item | Exact bundled dependency versions/licences unresolved | Resolve the v11.17.2 release lockfile and add required licence texts. |
| `swiftui-math-fonts` — product-decision item | Open in checker, but owner decision is recorded externally as KEEP all 12 for 1.0 in issue #148 comment 5868785863 | Retain the 12 notices/digests and reconcile the checker bookkeeping; this ledger does not waive the artifact check. |
| `theme-tomorrow-light` — E23 item | Naming/source decision | Existing provenance says the palette is GitHub-derived, not Tomorrow-derived; E23 must decide whether to rename or re-source it. |
| `viz-js` — source-location verification | Planned source URL; anonymous retrieval not verified | Existing `ARCHIVE_PLAN.md` identifies the exact Graphviz/viz-js material and digest evidence still required. |
| `viz-js` — `LC-02` | Graphviz/viz-js source package and build-script pinning open | Pin exact Graphviz 16.0.0 and viz-js 3.30.0 source/build material and hashes. |
| `viz-js` — linked-library review | Linked-library obligations open | Confirm whether the WebAssembly build links libraries such as expat and add notices if required. |

The checker reports these eight exact entries. The SwiftUIMath row is retained
bookkeeping: the owner’s KEEP decision is recorded in issue #148, but the
local checker still requires the corresponding inventory reconciliation. This
is not evidence that any source offer is publicly reachable.

## Corresponding-source preparation boundary

`ARCHIVE_PLAN.md` is the authoritative preparation plan. The repository has
not created public archives, changed source-offer URLs, generated a release
archive, signed an artifact, or claimed anonymous retrieval. The remaining
safe preparation steps are source/archive assembly and digest review only:

1. identify the exact D2 Go source revision and module licences;
2. identify the Graphviz/viz-js source and any linked-library obligations;
3. resolve Mermaid’s bundled dependency versions from its release lockfile;
4. obtain owner decisions for the font set and Tomorrow Light naming.

Only after an owner-authorized source-only publication may the URLs and
`source_offer.status` values be updated and the release candidate checked.
