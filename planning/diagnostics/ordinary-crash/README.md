# Capture an ordinary package-test crash without changing the tests

The combined MostlyText candidate can still leave inline styles different after
restoring full highlighting. Its separate passive trace did not reproduce that
failure. Ordinary CI on diagnostic head `8e6c7108ccc572c75c9aea54d1afa5d3a5127f89`
then terminated with signal 11 before reaching the restore cases. The last printed
test is not a crash diagnosis because the output is buffered. This bounded
experiment captures attributable process and stack evidence to guide a correction.
It makes no product or dependency change and is not a release candidate.

## Source and ordinary execution

The production Packages tree is frozen to candidate
`ad79f2773f2cbaf8bb78bdb796b1d11b411be79b`, package-tree object
`54fa64b226ee4cfbf35ee3edc9fce09c12e58b75`. The lock SHA-256 is
`9c7c1835b89d1248bd156e1caa45c7691098b36ef1aabea35a8974b5c15f8977`.
The runner checks clean source and all 22 clean dependency revisions before/after,
records the actual checkout head/tree and PR head/base, and writes outside the repo.

The ordinary workflow keeps `swift build --force-resolved-versions`. Only on the
`diagnostic/ordinary-crash-` branch does the Python wrapper launch the unchanged
`swift test --no-parallel --force-resolved-versions`, in the ordinary package
checkout. There is no prebuilt test copy or added `--build-tests` command. Standard
input/output/error, environment, working directory and process-group behavior are
inherited. The diagnostic uses setup-python to select Python 3.12; that action
changes infrastructure PATH/Python settings, but the wrapper adds no environment
overrides for the tested command. No test assertions, clocks, test selection, timeout, debugger, signals,
retries or extra test environment variables are introduced. Original output stays
in the ordinary Actions log; download its complete raw log after the run.

The original return code and any direct signal are retained. A direct signal maps
to the shell convention 128 + signal; Swift's usual child-failure exit 1 stays 1.
Observer/capture failures are reported separately and cannot replace a returned
test status or make failed tests pass. A separate workflow step checks diagnostic
integrity after the ordinary app/build gates. Capture files upload even after test failure. The unchanged later
app/CLI/build/test steps keep their ordinary success prerequisites.

## Process and report ownership

A passive poll every 100 ms observes the exact live child and only test helpers
whose executable and exact newly built bundle argument match. Parent birth
identity is checked at admission. Darwin's process birth seconds/microseconds and
executable path are read with libproc; argv is tied to a second identity snapshot
and never exported. Legitimate launcher exec and already-proven helper reparenting
retain their original birth identity. PID reuse and unknown short-lived helpers
are not inferred from later reports.

SwiftPM can use `swiftpm-testing-helper`, whose executable differs from the loaded
`MacDownKitPackageTests` image. Both are bound independently. File identity is
observed while the process is live; hashes and Mach-O UUIDs are collected only after
the command exits, with unchanged-file checks. These are executable identities,
not identifiers of the last active test case.

After command exit, UUID extraction, streamed binary hashing and report collection
share a 30-second budget. Each subprocess receives the remaining budget. On failure
the collector considers only fresh `.ips`
filenames for the observed executables in the user/system DiagnosticReports
folders. No unrelated filename, log or rejected report content is exported. A
report must match an observed PID, independently sealed executable UUID and
process birth time. Its executable path must be exact or use the single locally
observed Apple home-redaction form `/Users/USER/*/<owned basename>` for a binary
actually observed under the home directory. That form also requires an unambiguous
UUID match; basename alone never establishes identity. Other wildcard forms are
rejected. The artifact records which path binding was used. Printed birth time must have at least millisecond precision;
comparison permits only one unit of its printed precision for rounding. Capture
time must lie within the command interval (accounting for its printed precision).
A loaded test image must match the separate test-binary UUID and the same explicit
path rules. An owned helper or
launcher crash before the verified test image loads is labelled separately.

Missing identities, reports or precision yield unavailable evidence. No matching
report does not mean that no crash occurred. The snapshot can miss a helper that
starts and dies between polls. Observation can affect scheduling; this diagnostic
is not a new performance measurement.

## Bounded, filtered artifact

The collector opens candidates without following symlinks, verifies regular files
and stable metadata, and hashes exactly the bytes parsed. Apple header-plus-body
JSON and partial writes are handled without exporting fragments. Limits are 64
candidate files, 8 MiB per report, 64 MiB total, eight retained reports and 128
faulting-thread frames per report. Observations retain at most 16 owned processes
and four executable images per process; each binary is limited to 2 GiB and hashed
in 1 MiB blocks. Truncation/rejection is explicit.

Exported fields are allowlisted: process PID/birth/ancestry, executable name/hash/
UUID/path hash, exception type/signal and termination namespace/code, faulting
thread index, frame image offsets and referenced image UUIDs/base addresses.
Exception, signal, termination namespace and architecture strings use fixed enum
allowlists. Raw report symbols and image names are omitted entirely. Only the faulting thread is exported. No raw `.ips`, environment,
registers, memory summaries, app-specific messages, thread/queue names, unrelated
threads/images, account/device metadata, arbitrary source paths or parser snippets
are uploaded. Raw file bytes are transient in memory.

For attributable reports, `atos` may resolve frames against only the exact
UUID/hash-verified owned binary and test image while they still exist. Raw atos
output is not exported; symbols are separated from image/source-path suffixes.
Unresolved frames remain explicitly unsymbolicated. Hashes alone do not establish
successful symbolication. Unverified system frames retain only UUID/base/offset
evidence; the collector never opens report-supplied paths. Neither observer nor collector kills any process or
changes crash-reporting preferences.

## Verification and holds

Synthetic unit fixtures cover wrong PID/birth/path/UUID/time, missing identity,
launcher exec, reparenting, unobserved helpers, different helper/test-image UUIDs,
partial JSON, symlinks, size/frame/time bounds, private strings in otherwise valid
fields, unavailable final process identity, and original-result preservation on
observer/capture/final-write errors. `probe.py` runs one disposable owned C
process that deliberately faults after a short startup pause; it disables core
files only for itself, and checks an attributable symbolicated report. This is not
a product test, and a missing report remains a retained limitation.

Local validation on 19 October 2026 used one owned synthetic SIGSEGV process.
The first capture preserved -11 / shell 139 but rejected the Apple-redacted home
path. After independent review of the explicit redaction matcher, the same report
was reprocessed once against the retained binary: `synthetic_fault` and `main`
resolved, while one system frame remained unresolved. The original failed result
was retained separately; no second crash was run. The original report SHA-256 is
`0ed50610dec81ef31d05406569037c3cc2f8cd268ffd52317bea1c0eb01c28ef`;
retained binary SHA-256 is
`c74d63d900aca2d56062889be52af82410b14644db1ab580146e0b0bdc7dc563`.
This verifies local collector behavior only, not actual SwiftPM-helper capture.

The diagnostic needs final independent source/result review before push, then one
complete exact-head hosted result. Use an attributable stack for a focused
reproduction and reviewed correction if justified; do not rerun unchanged until
green or attribute a crash to the last printed test.

The 8,192 UTF-16 fallback, production dependency pins, experimental branch isolation,
PR #480 draft status, issues #53/#203 and owner/release gates remain unchanged.
Manual Pinyin coverage remains limited; automated XCUITest did not prove CJK.
Any production correction needs its own regression, independent review and exact
combined-candidate Release performance/required validation. No merge, distribution
signing, notarization, release or upstream submission is authorized by this diagnostic.
