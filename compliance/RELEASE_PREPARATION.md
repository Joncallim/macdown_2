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

The release check remains blocked by eight inventory items. No `status` field
was changed:

| Component | Current blocker | Material prepared or still required |
| --- | --- | --- |
| `d2` | Planned source URL; Go revision/module provenance open | Existing `ARCHIVE_PLAN.md` identifies the upstream package, one-line patch, archive digest and nested-module evidence still required. Do not publish or mark verified here. |
| `viz-js` | Planned source URL; Graphviz/viz-js source package and linked-library review open | Existing `ARCHIVE_PLAN.md` identifies the exact Graphviz 16.0.0 and viz-js 3.30.0 material and required digest evidence. Do not publish or mark verified here. |
| `mermaid` | Nested bundled dependency versions/licences unresolved | The inventory’s `nested` list is the source-grounded starting set. Exact lockfile resolution and verbatim licence texts remain required before release. |
| `swiftui-math-fonts` | Owner decision whether all 12 shipped fonts remain | All 12 notices/digests are already recorded; product decision remains open. |
| `theme-tomorrow-light` | E23 naming/source decision | Existing provenance says the palette is GitHub-derived, not Tomorrow-derived; E23 must decide whether to rename or re-source it. |

The checker reports eight failures because `d2` and `viz-js` each have two
release blockers, while the other three records have one each. This is
consistent with the current inventory and is not evidence that any source
offer is publicly reachable.

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
