# Capture the combined candidate's unexplained package-test crash

## Owner summary

Hosted CI for the reviewed #159 test candidate ended with signal 11 instead of a test assertion. The ordinary Actions log did not retain a crash stack, so it cannot show which code failed. This diagnostic runs the same locked serial package command with the previously reviewed passive crash collector. If the process crashes again, the collector may retain only an attributable, bounded stack. It does not change product code, test thresholds, test selection, dependency pins, release policy, or the original command's exit status. A clean diagnostic run would not explain or erase the failed run.

## Exact source and execution

- Product/package base: `7a7739cd8fdbf9ed22479a6926f84d5cd147b5ed`, the local #121 plus #159 combined candidate. Its `MacDown2/Packages` tree is `04a5b4e873b71d1a866dfb01f7b52c835f767367`; committed `Package.resolved` SHA-256 is `58585f78359b7ae6998ee1a83caf4f8bcc029858d2b1ad576e8436b48956c1c2` with 22 pins. The observer validates those values, a clean source tree, and clean exact dependency checkouts before and after the ordinary command.
- Trigger: one manual CI `workflow_dispatch` on this diagnostic branch. The special path is selected only when `github.ref_name` begins `diagnostic/ordinary-crash-`; normal branches still use the unchanged `swift test --no-parallel --force-resolved-versions` line. The diagnostic wrapper invokes that exact command once and returns its exit status.
- The collector comes from the independently reviewed [ordinary crash diagnostic PR #495](https://github.com/Joncallim/macdown_2/pull/495). This adaptation changes only the expected source/lock identities and the branch condition required for a manual dispatch. Its 26 controls pass locally. The workflow uploads the bounded artifact even on failure and checks capture integrity separately from the original test result.
- The collector accepts only a process proven to be the Swift Testing helper for this test image. It records bounded process identity and allowlisted faulting-thread image offsets; raw `.ips` reports, arbitrary paths, registers, memory, document data, and unrelated processes are excluded. No OS crash-reporting preference or security permission is changed.

## Interpretation and limits

- The triggering ordinary run is [39538431532](https://github.com/Joncallim/macdown_2/actions/runs/39538431532), exact `be80effc`, failed with signal 11 in package tests. Its raw log had no attributable stack, #159 assertion, or `CLEANUP_TIMELINE`; buffered output cannot identify a crashing test.
- A previous signal-11 run on a different head motivated the original collector, but that collector did not reproduce a crash. This diagnostic is a single attempt to capture a newly observed failure, not a retry-until-green. If it succeeds without a crash, the hosted crash remains unresolved. If it fails but no matching report is collected, the result is still unresolved. Only an attributable report or a deterministic source-level regression supports remediation.
- Diagnostic success is not CI clearance for PR #503/#504, signed folder-chooser acceptance, release-only compliance, release, or issue closure. The combined candidate requires its own ordinary hosted validation after a justified correction.
