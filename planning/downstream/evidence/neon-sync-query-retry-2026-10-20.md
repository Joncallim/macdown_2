# Retry a failed synchronous highlight query

## Owner summary

After a small Markdown edit, MostlyText can briefly leave inline code with the
wrong style even though a freshly opened view renders it correctly. A hosted
trace showed the synchronous Neon query met a still-pending parser and returned
an empty successful result. That marked the range as styled, so later work did
not revisit the inline span. The reviewed correction makes a synchronous query
error request Neon's existing asynchronous validation of the same range.
This preserves the 8,192 UTF-16-unit highlighting fallback and changes only
Neon's locked fork revision. It does not claim to solve every stale-highlight
path or close issue #203.

## Reproduction and diagnosis

The original PR #497 candidate is `29c3682e93729a5f53a4b67be4d91e052c97444d`,
with Neon `10df9b9dbba252b43edd0243c47143a3272bd408`.
[Hosted CI 39309259102](https://github.com/Joncallim/macdown_2/actions/runs/39309259102)
failed the startup render equality: the edited view had a heading run over
`0..<22`, while a fresh view had the inline-code run at `15..<21`. The cleanup
timing failure from earlier CI remains a separate gate.

The diagnostic-only head `7fc76c84968fd889609deaa4a2185e0acb7fa46f`
exported that candidate's unchanged package source with all 22 locked pins.
[Hosted diagnostic run 39353124711](https://github.com/Joncallim/macdown_2/actions/runs/39353124711)
reproduced the original editor assertion. Its integrity check passed, and four
complete trace sessions reported no dropped events. The retained artifact is
`/Users/jonathanlim/GitHub/_cleanup-archive/neon-current-trace-2026-10-20/hosted-39353124711/neon-current-trace-39353124711-1/`.

In `startup-single-edit-E1F1AA93-B571-4277-9CC3-D26223FFB12F.json`, the
edited client's query 21 covers `2..<96` while the parser is pending. It
throws `BackgroundingLanguageLayerTreeError`; Neon catches that and returns
`.noChange`. The non-nil empty application is treated as success by the token
validator, and the styler returns no next invalidation. The following edited
query 22 starts at 23, past the inline-code span. Fresh query 26 does write
the `{15, 6}` inline run. This chain explains the observed mismatch. The
trace's `validation.success` event near sequence 3196 belongs to query 18's
sublayer, not to query 21; the validator outcome for query 21 follows from
the implementation rather than that event.

The same diagnostic run's cleanup case passed locally to the hosted runner at
about 130.9 ms under the unchanged 150 ms bound. Both an independent Swift
watchdog and the Dispatch timer fired around 130 ms for a 25 ms requested
deadline. This shows delayed timer/scheduling delivery in that run, but does
not identify which scheduler stage caused it or prove the earlier 163 ms
failure. The historical cleanup failure is not dismissed as a flake.

## Change and controls

The isolated `Joncallim/Neon` fork branch
`fix/retry-synchronous-highlight-query-2026-10-20` contains reviewed commit
`dabf50c947148c49acd0d321dfe8f3805d10b3da`, based directly on `10df9b9`.
Neon's synchronous query catch returns `nil`, which asks its existing range
validator to queue the same range asynchronously. The asynchronous catch is
unchanged. An internal provider factory permits an injected synchronous
throw without changing the public production call path.

The fork's new Swift Testing regression injects that error, checks the nil
result, then explicitly requests the same range asynchronously and verifies a
nonempty token. A negative control restored the old `.noChange` response and
failed the nil assertion. The restored focused test, locked fork suite, and
locked fork build passed. The new test does not independently exercise the
automatic validator handoff or final editor paint; the generic validator and
MostlyText integration checks supply those layers of evidence. Independent
read-only review found no architecture or concurrency blocker, while noting
that all synchronous errors now get an async attempt and a later async error
can still return `.noChange`.

This candidate updates only the Neon revision in the MacDownKit manifest and
lock, its compliance inventory entry, and generated notices/SBOM. All other
21 package revisions and the Neon licence hash are unchanged. The deliberate
lock update used `swift package update Neon`; `compliance.py check` passed.
The initially focused locked candidate test selected
`HighlightingRestoreStartupTests|TextFilterBlockingCleanupDeadlineTests` and
passed both startup cases and both cleanup arguments. Its source was still
uncommitted, so exact-head validation is recorded separately after commit.

## Remaining gates

The candidate still needs exact-head full package and Release performance
validation, locked Release app/CLI and app-test validation, hosted CI, and owner
review. A green suite would not establish the strict 50 ms 1 MB Markdown edit
budget; issue #203 remains open. Issue #53 also remains open. Native manual
Pinyin evidence is limited to the journeys under
`planning/downstream/evidence/pinyin-native-manual/`; automated XCUITest did
not prove CJK coverage. PR #480 remains draft and unmerged. No master merge,
release, signing, notarization, upstream submission, or issue closure is part
of this candidate.
