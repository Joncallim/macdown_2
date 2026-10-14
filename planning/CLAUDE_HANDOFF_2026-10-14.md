# Claude handoff — 2026-10-14 integration checkpoint

Protected Claude work was not reset, rebased, edited, published, or merged.
The integration branch is `integration-queue-2026-10-14` at exact head
`82808fb1c33927cd2806f660c3c947197b4302c9`.

Existing draft lanes preserved:

- #473 / issue #159: `64e88dd`;
- #474 / issue #173: `997b9ac`;
- #475 / issue #88: `4a627ad`;
- #476 / Mermaid theme: `a944d09`;
- #477 / Graphviz theme: `4a1ea3b508d3647380220fede476299a54a15d9c`.

Added on the integration lane:

- `5e0c192bf4a9a2f38f57d912d40f17cf8e84c5b6` —
  `compliance/RELEASE_PREPARATION.md`, an explicit release-inventory ledger;
- `f97b7bfcb0b6f0cba7b36701e1f80cf5b89b9d19` —
  `planning/downstream/issue-53-handoff.md`, current-source reconciliation;
- `82808fb1c33927cd2806f660c3c947197b4302c9` —
  `planning/downstream/issue-441-cursor-boundary-diagnostic.md`, native cursor
  diagnosis boundary and reproduction matrix;
- this handoff file.

The #53 key-by-key map is substantive preparation, not a newly implemented
migration. It is checked against the original MacDown `MPPreferences.h/.m`
at upstream revision `3e2a2bf101c215c143bf00d9f857965f0ee82487`, and reconciled
with current `LegacyPreferencesDetector` and whole-domain JSON settings
storage. It deliberately records dispositions and required fixtures without
writing user preferences.

The #148 ledger records the tree check as passed and names the eight release
inventory blockers; it does not claim release clearance, signing, or source
archival.

Native #441 reproduction was not completed: this execution environment did
not provide a safe interactive desktop session with which to inspect actual
pointer transitions without disrupting the user's activity. Source inspection
found no existing cursor policy, but that is not treated as a root cause or
proof that an isolated fix is impossible. Native reproduction remains an
acceptance item.

No issue is claimed closed by these preparation commits.
