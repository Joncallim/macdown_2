# Issue #148 — Licensing, provenance and exact-artifact compliance

## Owner summary

The compliance tooling, dependency lock, inventory and generated notices/SBOM are merged. What remains is making the corresponding source publicly and anonymously retrievable, shipping the notices and licence screen in the app, and verifying the exact final artifact. This document records the intake that the earlier hand-off set lacked and the resolution of the source-archive deadlock. It authorises nothing: publishing source, building candidates and promoting software are separate owner decisions.

Reviewed baseline: master `202ec7d8fed2cd4c49152b80983c9d9ecf0e9d47`, 2026-10-09.

## Deadlock and resolution

`compliance/ARCHIVE_PLAN.md` verified anonymous retrieval from packages attached to a **draft** GitHub Release; drafts are unpublished and access-controlled, and the E17 script checks `source_offer` before notarisation in release-candidate mode. Both cannot be satisfied: the final candidate and #148 could never finish. Resolution (prose, graph and checker agree): the corresponding source is a separately authorised, **source-only** publication (`source-archive-authorization` → `source-archive-published`), done BEFORE the final candidate so notices embed frozen, working URLs and digests. No application binary is made public to satisfy the checker; the compliance gate is not weakened (`compliance_gate_weakened: false`).

## Units

1. `source-archive-authorization` (input, owner): approval to publish the source objects publicly.
2. `source-archive-published`: publish immutable versioned objects (packages, patch, licence texts, `SHA256SUMS`, notices/SBOM copies, index pages) to the durable location; freeze URLs and digests; set `source_offer.status` to `verified` only with recorded no-cookie retrieval output.
3. `artifact-compliance-148` (verification, after the final candidate): `compliance.py check --release --artifact <app>`, notices/SBOM byte-for-byte equal to the archive copies, in-app licence screen and bundled obligations (LICENSE/THIRD_PARTY_NOTICES in the bundle, About/Licences UI) present in the exact artifact.

## Tests and evidence

Anonymous fetch of a draft-release asset fails (kept as a documented counterexample); published objects fetched without cookies match `SHA256SUMS`; the shipped notices name exactly those locations; no binary is reachable from the source location. Open compliance items are tracked in the inventory and `compliance.py check --release` output; none may be marked verified by inspection alone.
