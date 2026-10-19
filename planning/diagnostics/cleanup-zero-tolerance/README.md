# Observe cleanup with explicit zero sleep tolerance

The hosted cleanup watchdog started promptly but returned from its deadline sleep
after the unchanged 150 ms assertion bound. This isolated diagnostic removes the
clock implementation's default sleep tolerance as one variable. It changes no
editor behavior and is not an adopted cleanup correction. A pass cannot establish
that timer coalescing caused the historical failure, because executor and host
scheduling can also delay resumption.

## Evidence and hypothesis

[CI 39244808783](https://github.com/Joncallim/macdown_2/actions/runs/39244808783)
tested crash-observer head `38427ff6d47359876f616c6414bda41e672db49e`, synthetic
merge `d2f6edec2b501435a59e7b5dd749fdbf1ffe6c54`. Its package command completed
normally with exit 1 and three unexpected cleanup timing assertions. The two
other issues were declared known Neon issues. Both restore-style cases passed;
no signal crash recurred and scoped collection found no matching report.

With a configured cleanup timeout of 25 ms, the zero-delay case recorded cleanup
175.980208 ms and whole-call 177.321667 ms. The delayed-setup case recorded cleanup
160.537625 ms. Watchdog entry occurred 0.041041 / 0.023333 ms after cleanup start;
its post-sleep markers occurred at 175.929583 / 160.487500 ms. Gate completion
followed promptly. This locates the dominant interval around the sleep await but
does not distinguish timer delivery from task resumption or observation effects.

Swift 6.2 documents that an omitted tolerance allows deadline adjustment to
coalesce CPU wake-ups. The bounded source review did not establish a numeric
default tolerance or a mechanism predicting this observed delay. See the
[immutable Swift source](https://github.com/swiftlang/swift/blob/1ff1cc1170617ab23ab74aa8b741c8daca1903f6/stdlib/public/Concurrency/ContinuousClock.swift).

## Exact isolated change

The only package change from the production candidate is in
`Tests/TextFiltersTests/TextFilterFixtureOwnershipSupport.swift`: the real-clock
default changes from `ContinuousClock().sleep(until: deadline)` to
`ContinuousClock().sleep(until: deadline, tolerance: .zero)`.

The absolute deadline, capture before cancellation dispatch, 25 ms timeout in
the blocking regression, 150 ms assertions, body setup, cancellation behavior,
first-result arbitration, timing markers, test selection and command exit status
remain unchanged. Injected deterministic clock tests remain unchanged. Explicit
zero tolerance does not guarantee that a ready task resumes at the deadline.

Production candidate `ad79f2773f2cbaf8bb78bdb796b1d11b411be79b` and crash-only head
`38427ff6d47359876f616c6414bda41e672db49e` remain preserved. The production package
tree is `54fa64b226ee4cfbf35ee3edc9fce09c12e58b75`; this diagnostic's package tree is
**e690fa0cf0655c2a26889b53ca467feda05ee82c**. The collector explicitly requires the
latter, clean source and all 22 clean pinned dependencies before/after. No check
is bypassed. The lock SHA-256 remains
`9c7c1835b89d1248bd156e1caa45c7691098b36ef1aabea35a8974b5c15f8977`.

## Fixed validation and interpretation

After independent source review, run this variant's unchanged full ordinary CI
once on the hosted toolchain that exhibited the failure. Retain the actual
tested merge/tree, complete raw log, helper identity, before/after provenance,
original result and timing observations. Run heavy work serially. Do not rerun
unchanged until green. Static checks and collector synthetic controls must pass
before publication; the hosted ordinary suite supplies compile/regression
validation, avoiding an extra local run on a different toolchain.

If cleanup still fails, zero tolerance was insufficient in this execution; do
not relax the bound. If cleanup passes, it supplies a result for this variant,
not causal proof or release acceptance. Further attribution needs timer-delivery
and task-resumption evidence, or a deterministic causal regression. Any proposed
adoption must receive independent review and actual combined-candidate validation.

The 8,192 UTF-16 fallback, production dependency pins and isolated experimental
branches are unchanged. PR #480 remains draft/unmerged; issues #53/#203 and
native, compliance, warning, private-scanner, CJK-coverage and owner gates remain
open. No merge, distribution signing, notarization, release or upstream submission
is included. Prior Release performance evidence belongs to the unchanged
production candidate, not this diagnostic's CI timings.
