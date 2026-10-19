# Independent combined-validation review

Reviewed clean code head `400d475caaae130cdce1f6de4c6904027e700827` and the retained
one-shot evidence. Read-only review; no tests, builds or implementation changes.

No material provenance or test-selection defect was found. The reviewer independently
confirmed all 26 command-log hashes and the source archive hash; exact equality of
415 enumerated and executed app-case identifiers (413 pass, two existing disabled
PDF cases); absence of both benchmark methods; and the functional teardown pass.

Package evidence preserves two unchanged Neon known issues. The opt-in reconciliation
measurement suite was skipped, while both parameter cases of idle restoration and
whole-call cleanup passed. Those local Debug passes do not explain historical
hosted overruns. The PDF disabled annotations and Neon expected-failure tests are
byte-unchanged across the complete overnight source range.

All 167 artifact file hashes and sizes match the retained app. The 15 compared
resources include all 12 fonts, Prism, LICENSE and notices. Both checkout pools
(44 clean checkouts) match the production lock. First-party app/CLI compiler commands
contain warnings-as-errors with Debug `-Onone` and Release `-O`, and no
suppress-warnings flag. Existing build-system diagnostics remain unresolved.

Source and artifact release checks retain the same seven findings. The current
Release executable is thin arm64 with only a linker-generated ad hoc signature.
App tests ran in Debug; native UI was compiled only.

The reviewer identified an additional reporting qualification: the app log reports
101 and 102 live NSWindows. This does not establish a new leak, but the functional
teardown test cannot prove whole-suite window retirement. The warning is now explicit
in runtime-diagnostics.json, the evidence README and owner checkpoint.

Historical performance/hosted failures, PDF execution, native CJK coverage, preview
resource ownership, warning diagnosis and owner acceptance remain open. This is
bounded non-performance validation, not performance or release approval.

## Final document review and earlier window evidence

The reviewer also read the owner checkpoint, evidence README and updated runtime
diagnostic record. No material overclaim was found. Retained earlier app logs
show 101/107 live windows on clean `f9f9926f`, 101/104 on `95c3d25f`, and 101/102
on clean `0b85e6f0`, before the settings, preview and licence slices.
`window-warning-history.json` records exact log/command paths, hashes and excerpts.
Different test populations and executions do not establish a trend or leak cause.
The warning remains unresolved; later fixes must be driven by a discriminating
reproduction or ownership evidence rather than inferred from this count alone.
