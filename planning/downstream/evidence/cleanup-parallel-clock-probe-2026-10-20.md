# Compare cleanup watchdog wake paths under the same fixture load

## Owner summary

The combined-release branch's exact-head CI failed a test-fixture cleanup
bound: a requested 25 ms watchdog sleep woke after 156.36 ms, and the whole
fixture took 158.07 ms against its unchanged 150 ms bound. This diagnostic
adds two observation-only clocks to that test. It can identify whether the
delay is confined to Swift's watchdog, shared by other timer delivery, or
visible to an independently sleeping worker. It does not fix the failure or
declare a later pass sufficient release evidence.

## Baseline and experiment

The parent is combined head `7ff3ca9ab12c44d9c513806da721a19d20500f8b`.
Its [hosted CI run 39369127770](https://github.com/Joncallim/macdown_2/actions/runs/39369127770)
failed only the zero-setup argument of
`TextFilterBlockingCleanupDeadlineTests.cleanupDeadlineIncludesBlockingCancellationDispatch`:
whole call 158.072416 ms, cleanup 156.426291 ms. Cancellation dispatch,
watchdog start and gate completion consumed less than 0.1 ms each; the
watchdog returned from the requested 25 ms sleep at 156.357833 ms. A separate
200 ms setup argument passed with cleanup 35.176041 ms. The complete raw job
log was inspected; the shorter failed-step view omitted the later failure.

The test now starts a one-shot zero-leeway Dispatch timer and a high-QoS
worker that sleeps 25 ms at the same cleanup boundary. Neither can complete
the cleanup gate. Their start and return times are added to the existing
`CLEANUP_TIMELINE`, and `CLOCK_PROBE_FINAL` waits for both observations only
*after* the original bounds have been asserted and fixture cleanup is done.
The 25 ms fixture deadline and both 150 ms assertions are unchanged.

Compare one failing invocation, not separate runs:

- Swift watchdog late, other paths prompt: Swift timer/executor delivery is
  implicated; inspect the handoff before changing the timeout mechanism.
- Swift and Dispatch timers late but sleeping worker prompt: timer delivery is
  implicated. All three late after prompt starts suggests broader scheduling
  starvation or host suspension; a late worker start instead points to queue
  admission. These observations narrow causes but do not alone prove one.
- Clocks prompt but the gate or fixture return late: investigate cleanup gate
  logic and actor scheduling after the wakeup.

## Local validation and limits

The focused Debug test passed with forced package resolution, strict lint and
format passed, and no tracked dependency pin changed. On a quiet local Mac,
the two observed cases had cleanup intervals 29.447208 and 28.974667 ms.
Their workers returned at 25.330625 and 26.581 ms; Dispatch timers at
29.316042 and 28.822167 ms; Swift watchdogs at 29.329 and 28.844542 ms.
Both final probe records were complete. This validates observation and joins,
not the hosted failure's cause. A hosted full-suite diagnostic is needed
because it puts the three clocks in the same loaded invocation. No issue is
closed by this test-only change.
