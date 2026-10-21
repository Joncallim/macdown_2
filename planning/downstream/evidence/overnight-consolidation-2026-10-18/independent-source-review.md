# Independent overnight source review

Reviewed range: `60f779fc0f7324cd5dd3b7b503030e9c22d7d44f..400d475caaae130cdce1f6de4c6904027e700827`.

No new material code or tooling findings. Inspected HEAD was clean `400d475c`.
Review was read-only; no builds, tests or benchmarks were run by the reviewer.

The combined changes remain coherent:

- Preview disposal invalidates navigation ownership and scheme-delivery tokens before stopping WebKit. Scheduled-attempt identity also protects same-generation retries from process recovery.
- Settings distinguish missing `showsStatusBar` from malformed/null values without changing valid booleans. UUID-domain fixture isolation avoids interference with the window fixture.
- The original zero-delay 150 ms whole-call contract remains enforced; phase timing adds diagnosis rather than replacing that assertion. Highlighting tests retain a non-vacuous pre-idle assertion and final styled-run comparison.
- Window teardown now uses normal close/disposal paths outside measured benchmark intervals. Its functional regression remains useful independently of the two benchmarks.
- Licence packaging adds the actual licence/notices resources and explicit Textual Prism attribution. The separate Mermaid audit remains partial; Prism evidence does not close its nested obligations.
- The syspolicy_check stub isolates release fixtures, while the negative control preserves failure-before-final-hashes behavior. It proves script control flow, not actual signing or distribution acceptance.

Selection review:

- Exclude only the two timed WholeAppTabScalePerformanceTests methods; retain teardownRetiresTheWindowAndItsBackgroundWork.
- The expanded package regex correctly catches the FileTree benchmark and separately named caret/per-keystroke budgets.
- Retain MarkdownTreeReuseTests, functional deadlines and boundedness regressions.
- InlineResolutionReconciliationTests is another measurement suite outside that regex. The retained environment record shows its enabling variable absent; confirm the actual test log records it skipped.

Remaining limits:

- Synthetic navigation/delivery regressions and the Markdown window teardown test do not prove closing a native HTML window with active resource work.
- Delayed requests can still use the newer mutable resource root; explicit directory grants, immutable ownership, filesystem-race containment and worker/drain/quota work remain open.
- Settings protected writes, later unreadable generations, non-Data preservation and legacy migration remain open.
- Prior performance and hosted cleanup failures remain failures. Native CJK coverage, owner acceptance, seven release-compliance findings and distribution signing remain separate gates.

The one-shot combined non-performance validation was still in progress at review completion. This source review is not performance or release approval.
