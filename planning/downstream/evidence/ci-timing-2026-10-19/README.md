# Cleanup deadlines and idle-restore regression evidence

## Owner summary

The editor still reduces Markdown highlighting above 8,192 UTF-16 units and
restores it only at or below 6,144 units after two seconds idle. This change
makes that idle contract testable without depending on how quickly a hosted
runner wakes a test. It also starts the test-fixture cleanup deadline at the
end of the fixture body, before cancellation and watchdog dispatch can consume
part of that budget. The original 150 ms cleanup assertions remain unchanged.

The intended user outcome is unchanged: editing remains responsive in reduced
mode, and a canceled restore must not repaint or clear a newer restore. The
production sleep remains `Task.sleep(for: delay)`; an internal optional sleep
closure is nil in production. Dependency pins, fallback policy, and cleanup
first-arrival arbitration are unchanged. This is local regression evidence,
not completion of the release or native input-method gates.

## What the failures establish

Hosted run [39140426985](https://github.com/Joncallim/macdown_2/actions/runs/39140426985)
failed the early-restore and styled-run expectations, and cleanup took about
160.18 ms against its 150 ms bound. Lint and compliance passed; later app/CLI
build and app-test steps were skipped. The integration head was
`8b324fb14cc82fa3dbec04203f9ea18e24985d46`; the hosted merge revision was
`9dd3436`.

Later run [39176035861](https://github.com/Joncallim/macdown_2/actions/runs/39176035861)
also failed style equality and the cleanup bound (152.56 ms). Diagnostic run
[39177890173](https://github.com/Joncallim/macdown_2/actions/runs/39177890173)
failed the requirement that a real-clock observation occur before the idle
interval expired. That nonfatal expectation did not prevent the following
style comparison from running; style equality did not fail in that run.
Neither result establishes the cause of the historical styled-run mismatch.
It remains unresolved and must not be labeled a flake.

Source inspection showed that cleanup previously began a relative sleep only
when the watchdog task ran. Cancellation and scheduling delay could therefore
extend the requested budget. The new absolute monotonic deadline begins after
the body returns, before that dispatch. Fixture setup remains outside the
cleanup interval. A scheduler can still wake late; this is not a hard real-time
guarantee and does not relax the wall-clock assertions.

## Regression coverage

The controlled idle tests use the actual editor and highlighter, advance only
the idle sleep, and await every released restore task before observing its
result. They cover the original four edits with and without an idle pause,
registered and not-yet-registered canceled waits, distinct replacement waits,
marked-text retry, language change, teardown, and draining before allocation.
The separate default-clock path retains the real rendered-style comparison and
its failure diagnostics.

Cleanup tests verify the exact absolute deadline when the watchdog starts late,
both acknowledged result attempts at the actual first-arrival gate, and
cancellation observed inside the actual aggregate child join. Failed
observations release held waits and join the retained fixture owner before
removing its directory. A separate control exercises that failure cleanup path.

Independent source review initially rejected four gaps: a terminal drain that
could hang before registration, an unbounded result wait, a weakened
cancellation assertion, and competing gate attempts that were not acknowledged.
All four were corrected and reviewed before the validation recorded here. The
manual sleeper was subsequently split into its own file to satisfy the existing
file-length rule; independent review verified byte-equivalent logic.

## Verification and provenance

Validation ran on CORTANA with Xcode 26.6 (17F113), Swift 6.3.3, on branch
`review/159-validation-gates` over parent
`b37f25e954c7dae3a948fb454ec6ccd2c750dd58`. The ten changed Swift files are
identified by `source-sha256.txt`. Their bytes matched before and after the
initial focused pass and the final run after both mutations were restored.
The committed package lock remained SHA-256
`9c7c1835b89d1248bd156e1caa45c7691098b36ef1aabea35a8974b5c15f8977`.

The final restored-source command was:

```sh
cd MacDown2/Packages/MacDownKit
swift test --force-resolved-versions --no-parallel --filter 'HighlightingSizeFallbackTests|HighlightingSizeFallbackLifecycleTests|TextFilterFixtureCleanupSafetyTests|TextFilterBlockingCleanupDeadlineTests|TextFilterFixtureCleanupOrderingTests'
```

It exited 0: all five selected suites passed, with no skipped cases or compiler
warnings. `restored-focused-tests.log` retains the complete output. Strict
`swiftlint lint --strict MacDown2`, `swiftformat --lint MacDown2`, and
`git diff --check` passed on the identical source snapshot.

Two single-run negative controls proved the assertions detect the intended
faults. Each compiled successfully and exited 1 because of test failures:

- Changing the call to `scheduleRestore(after: .milliseconds(10))` failed both
  parameter cases at the requested deadline (0.01 versus 0.2 seconds) and the
  premature full-mode assertion. See `early-restore-negative-control.log`.
- Removing only the forwarding `joinTask.cancel()` from the fixture's
  cancellation handler failed the actual child-cancellation acknowledgment.
  The test then released and joined its work and finished, without hanging.
  See `aggregate-cancellation-negative-control.log`.

Both mutations were restored byte for byte before the final focused pass.
`logs-sha256.txt` identifies the retained logs. Full before/after snapshots,
mutation patches, restoration records, lint logs, and independent review are
retained locally under
`/Users/jonathanlim/GitHub/_cleanup-archive/timing-correction-b37-2026-10-19/`.
Earlier 14:10/14:11 local logs lacked a matching complete source manifest; a
14:15 attempt failed compilation and ran no tests. None is used to validate
this candidate.

## Remaining gates

These results do not establish a hosted CI pass or final combined-candidate
Release performance. Those require the actual combined head and fresh evidence.
Historical styled-run mismatches remain unexplained. Native manual Pinyin
coverage is limited to the journeys recorded in
`planning/downstream/evidence/pinyin-native-manual/`; automated XCUITest did not
prove CJK coverage. The owner's review and the other release-hardening gates
remain required. Issues #53 and #203 remain open until their full criteria are
met. No dependency experiment, master merge, release, signing, notarization, or
upstream submission is included.
