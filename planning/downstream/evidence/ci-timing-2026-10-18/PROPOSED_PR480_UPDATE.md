# Proposed PR #480 evidence update — not posted

This is a reviewable addendum for the existing draft integration PR, contingent
on separate review and explicit authorization. It does not replace that PR's
broader integration description or approve merging. The current remote head is
`60f779fc0f7324cd5dd3b7b503030e9c22d7d44f`; the base is
`4aa46bfa6b91bf1c1d218b9b1f67480312f66396`.

## What this changes

Correct idle-restoration assertions, preserve the original whole-call cleanup
deadline, retire benchmark windows through normal disposal, and run UI/view
tests on their required actor. The accompanying production warning cleanup uses
Foundation's current failing-URL key for preview-load classification and removes
unused calculations/bindings and a redundant typed catch.

## Why

The inherited CI failure required checking what the tests actually promised.
A legal idle restoration could fail the typing assertion. The first local
cleanup measurement was too narrow and has been corrected. Separately, a
benchmark left real window work alive and delayed a later close test by about
a minute in controlled runs. Fresh compilation exposed actor-isolation mistakes
that incremental builds had not recompiled.

## How it works

The restoration test distinguishes an editor awaiting idle restoration from one
already restored. The cleanup test retains the zero-delay call-to-result bound
and records setup and cleanup independently. Benchmark teardown removes its
controller, closes its window and uses isolated preferences/session storage.
Test lifecycle hooks and status-view suites use the main actor. No production
dependency, highlighting cutoff or timing limit changes.

## What I should test

Review the negative controls and exact-source evidence in
[FOLLOWUP.md](FOLLOWUP.md). Exercise the final native editor/close and input-method
matrix on an available desktop. Preserve the narrow scope of the existing
Debug-only Simplified Pinyin evidence. Reconcile the failed Release parser
measurement before treating performance acceptance as complete.

## Risks and limits

This is not a green release candidate. A planned Release performance run failed
the direct Markdown parser ceiling at 484.814584 ms against 400 ms; subsequent
instrumented samples do not explain or replace it. Hosted cleanup overruns and
the original highlighting run mismatch remain unexplained. AppKit/SwiftUI runtime
diagnostics and Xcode dependency-scan warnings remain. Native UI execution,
independent/owner review and eight release-compliance requirements are pending.
#53 and #203 remain open. The large-file fallback is containment, not proof of
the fully highlighted product performance target.

## Verification

The final code is `0b85e6f09dc3bba82a0da3b15f1583b3263fcb74`. Unsigned Release
app/CLI builds and the app-target suite pass with Swift warnings treated as
errors for app-owned targets. The formerly slow close case takes 0.601 seconds
in the full run. The full package suite passed on `95c3d25f`, whose package tree
is byte-identical, with two existing known Neon issues. Lint, format, clean-source
compliance and lock checks pass. The Release performance gate remains failed;
no hosted result exists for these local commits.

If authorized after review, fast-forward remote `integration-final` to the
accepted local `fix/ci-timing-contracts` tip and use this evidence in the existing
draft PR #480. Recheck remote identities before acting. No push or PR edit is
authorized by this file itself; do not merge or publish a release.
