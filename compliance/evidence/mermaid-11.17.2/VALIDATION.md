# Mermaid audit checkpoint validation

## Owner outcome

The shipped Mermaid artifact now has reproducible module/source-map evidence.
The offline replay and full compliance test suite pass on the combined local
candidate. This does **not** finish the nested attribution inventory or approve
distribution: release preflight still fails eight requirements. No editor
behavior, runtime resource, dependency pin or distributed notice changed.

The audit was committed as `1350ff78050dcb80d600e8f2d9fa5b4b8dcc4dd9`. Final
validation used a clean `git archive` of the combined audit and test-fixture fix,
**`0ede2f3ad4daf55d4bb1edfe34161cddb57a5d2b`**, on CORTANA, 2026-10-18 UTC.
The subsequent evidence-only commit does not change the tested tools or tests.
[validation.json](validation.json) records commands, timestamps, exit codes,
source archive and evidence hashes. It distinguishes initial failures from final
results rather than overwriting them.

## Checks and their limits

| Check on `0ede2f3a` | Outcome |
| --- | --- |
| Full `python3 -m unittest discover -s compliance/tests` | Passed: 81 tests, including 15 source-map negative controls and the release-fixture distribution-check failure path. |
| `compliance.py check` on clean committed source | Passed, zero unverified items in tree mode. This is not the release gate. |
| `compliance.py check --release` | **Failed: eight requirements remain open.** Its exit 1 is the preserved release-blocking result, not a passing compliance result. |
| Offline artifact audit | Passed all captured archive, source/map and selected-text checks; still reports partial attribution. |
| Replay compared with committed report | Byte-for-byte equal, SHA-256 `6183e8177380457abbe5522f173ac844da1a4ae6609408c7d5de727a306609cb`. |
| Committed diff whitespace and production-file comparison | Passed; `MacDown2`, inventory, existing licence texts and generated notices/SBOM unchanged from `40b25974`. The production release script is also unchanged. |

The clean archive excludes the existing ignored generated app `Info.plist`,
which is already documented as causing an unregistered-file finding in a scan
of the build worktree. It was neither deleted nor registered to silence the gate.
No app build, native UI operation or performance rerun was needed for this
compliance-only change. The app tree remains
`929fe5add3fc84a6038ad0f8bf7e14a211fca2f5`, identical to the previous validated
code at `0b85e6f09dc3bba82a0da3b15f1583b3263fcb74`. Its unresolved Release results
remain **484.814584 ms / 400 ms parser** and **56.881709 ms / 50 ms editing assist**.
This checkpoint supplies no new explanation for either result.

## Failures found during validation

The first full suite on `1350ff78` stopped eight release-fixture assertions. A
captured `bash -x` trace showed the sandbox denied `/dev/fd/62` at process
substitution, before fixture preflight. One permitted rerun of the unchanged
suite then reached two failures from the host's real `syspolicy_check`: the
existing fixture omitted that tool from its stubs, so macOS inspected a fake
app and returned 70. These are distinct, evidenced causes; neither was dismissed
as a flake.

Commit `0ede2f3a` adds only the missing fixture stub and a failure control. Both
dry-run and release-candidate modes must preserve exit 70, omit final hashes and
omit the success message. The success path must call the stub. Real signing,
notarisation and build tools remained stubbed throughout; the host distribution
check performed a read-only inspection of the temporary fake app. No actual
signing, submission or distribution result is claimed. The final full suite ran
once after this reviewed correction, with process substitution permitted.

## Independent review

The separate reviewer independently checked archive integrity, exact shipped
bundle/map and parser pairings, composed counts, the 1,239 reported package
source rows and all 74 selected licence texts. Review found and resolved:

- FastDom's MIT text in its README and a licence-named Cytoscape tool incorrectly
  selected by the initial filename heuristic.
- The type-only nature of the Rough.js patch.
- Ambiguous duplicate source-map coordinates and out-of-bounds composition
  lookups, now rejected with negative controls.
- An overbroad resolution claim: the final report separates 72 versioned-map or
  parser records from two content-matched candidate versions. The lockfile is
  hashed, not parsed or used as inclusion proof.

Final source/evidence review reported no remaining material contradictory claim.
A separate review of the fixture correction found no concrete issue. Reviewed
generator SHA-256 is
`066bc7f8d56595af646816b8638f5c499e27c61516b5e0df6d203288859fc75d`;
reviewed fixture SHA-256 is
`a12ee89a25901be5ce4bec4099083f15741df3c9903a025000b97492c4a8bd69`.
The reviewer performed no edits or test runs. Author validation and independent
source review remain distinct; neither replaces owner acceptance.

## Remaining work and safe next slice

The [audit README](README.md) names the concrete KaTeX/React, Cytoscape borrowed
code, Rough.js prebundle, candidate-version and 3,980 unmapped-position gaps.
Finish those links before installing a complete inventory and notices/SBOM.
The decoded publisher attestation was not independently signature-verified.
The eight release failures also retain the D2/Graphviz source-publication and
linked-code requirements, font inventory reconciliation and Tomorrow Light's
E23 decision. The recorded font KEEP decision is not reopened.

If work moves to an independent issue, the bounded next intake is #53: reconcile
the existing legacy-key table and SETTINGS-COMPAT criteria with current source
and fixtures. `EditorSettings` now explicitly decodes a missing status-bar field,
and `SettingsCompatibilityTests` already covers older blobs, explicit false,
invalid values, unknown versions and corrupt data. Do not reimplement the stale
synthesized-decoder finding. Identify any actual missing fixture and the absent
machine-readable key coverage without reading real user preferences or adding
import writers. The existing E22/E23 boundaries remain binding.

The integration worktree is owned by this Astra task. The observed Claude
processes had working directories outside it and were not interrupted; no active
Swift/Xcode/test job competed at intake/checkpoint. Master and the dependency
experiment remain separate. Nothing was pushed, no PR or issue changed, and no
source or binary was published. PR #480 remains draft/unmerged; #53, #148 and
#203 remain open. Owner review and explicit authorization for external changes
remain pending. No action was denied by automatic approval review.

Raw evidence and all failed attempts remain in
`/Users/jonathanlim/GitHub/_cleanup-archive/mermaid-148-40b25974-2026-10-18/`.
The committed [evidence manifest](evidence-manifest.json) hashes captured inputs,
logs and review records; final clean-head ownership is separately recorded as
`final-checkpoint-provenance.json` in that directory.
