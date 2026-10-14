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

## 2026-10-14 implementation checkpoint

Commit `1a6e9a7b2665a2e43b9e306105b96c6543437c99` is the only new source
implementation after the published documentation branch. It changes exactly
two files: `MacDown2/MacDown2/WindowCoordinator.swift` (7 insertions, 1
deletion) and `MacDown2/MacDown2/WindowCoordinator+OpenDocument.swift` (5
insertions, 2 deletions). It adds the missing folder-search request gate and
pending-reveal state, and threads a MainActor `shouldContinue` callback through
the async open path. This is a bounded #173 lifecycle/compile fix; it does not
touch parser, highlighter, save, or recovery code.

Verification at that head:

- current-head app build via `xcodegen generate --spec MacDown2/project.yml`
  and `xcodebuild -project MacDown2/MacDown2.xcodeproj -scheme MacDown2
  -configuration Debug -derivedDataPath .app-build build
  CODE_SIGNING_ALLOWED=NO`: `BUILD SUCCEEDED`;
- `swift test --package-path MacDown2/Packages/MacDownKit --filter
  WorkspaceSearchEngineCancellationTests`: 5/5 passed;
- `swift test --package-path MacDown2/Packages/MacDownKit --filter
  SettingsCompatibilityTests`: 9/9 passed;
- independent reviewer: same-task self-review (no separate reviewer agent was
  available); it found MainActor serialization, generation invalidation, and
  pre/post-open stale completion guards correct. No remaining compile finding.

The #53 compatibility code and tests predate `1a6e9a7`; they were verified,
not authored by this implementation checkpoint. The Mermaid provenance audit
and lock-resolution tooling likewise predate this commit; it records official
commit `dcb694d`, exact lock resolutions, bundle hash, and root MIT license
match, but does not claim nested notices or source-map linkage complete.

Remaining concrete gates:

- #173: native acceptance across background tabs, zero-size/pre-attachment
  reveal, stale cancellation, and no focus/source/undo mutation still needs
  broader app-level evidence;
- #441: current-head app launched successfully, but computer-use cannot expose
  cursor identity/shape, so no cursor fix is justified and native cursor
  acceptance remains open;
- #53: legacy importer and final parser/theme dispositions remain outside the
  bounded compatibility slice and require Claude’s E22/E23 integration;
- #148: ledger/provenance is prepared, but nested notices, source archives,
  release inventory decisions, and legal/release gates remain open.
