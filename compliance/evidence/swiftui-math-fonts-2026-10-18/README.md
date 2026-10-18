# Retain the recorded 1.0 math-font set (#148)

MostlyText keeps all 12 SwiftUIMath fonts for 1.0. The inventory previously
reported that choice as undecided even though the release ledger already
recorded it. This correction removes only the obsolete decision entry and
records its source in the component notes. It does not change math rendering,
font selection, bundled files, licences, dependency versions or artifact checks.

## Decision evidence

The read-only issue retrieval on 2026-10-18 found five comments. Both
[#148 comment 5867001043](https://github.com/Joncallim/macdown_2/issues/148#issuecomment-5867001043)
and [comment 5868785863](https://github.com/Joncallim/macdown_2/issues/148#issuecomment-5868785863)
record the owner's KEEP-all-12 decision. No later reversal appears in those
returned comments. They were posted under Joncallim through Claude; they are
historical decision evidence, not a new direct owner instruction or release
approval. `compliance/RELEASE_PREPARATION.md` already required this bookkeeping.

Baseline: `aaec07288f96348fa6de651554991a865f1e4e96`. Its clean source archive passes
ordinary compliance and fails release compliance with eight entries, including
the obsolete font decision. That original output is retained. Only
`swiftui-math-fonts.open_items` and `.notes` change in inventory; all 12 resource
names/digests, licence texts and other component fields remain identical.

## Verification contract

Record the committed candidate, source archive and exact command results in
`validation.json` after validation. Required checks are source compliance,
release compliance with exactly the other seven findings, the existing compliance
regressions, generated-output identity, unchanged product/pins, and a direct
artifact check using the retained unsigned Release app from the previous preview
checkpoint. Reusing that artifact requires proving the complete product tree and
distributed notices are identical to its validated source; it is not a new build
on the bookkeeping commit. The final signed artifact still requires its own check.

The same checkpoint adds the independently reviewed
[preview directory-grant proposal](../../../planning/downstream/issue-121-directory-grant-proposal.md).
Its unresolved permission/user-experience decision remains explicit; no preview
grant code is integrated. No new performance pass or native WebKit security claim
follows from this inventory correction.

Raw evidence is retained locally at
`/Users/jonathanlim/GitHub/_cleanup-archive/preview-grants-fonts-aaec0728-2026-10-18/`.
No issue closure, push, source publication, signing, notarisation or release is
authorized by this checkpoint.
