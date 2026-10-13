# Release-configuration performance suites, one run

- **Source:** `cec1d28e3cc8976221f6e85b54cf2edaf333f426` (master after #468). Evidence files added afterwards; no source change. (Taken on `cec1d28e`; the later change to `268bee5f` is the ⌘F menu binding and UI tests only.)
- **Command:** `cd MacDown2/Packages/MacDownKit && swift test -c release -Xswiftc -enable-testing --no-parallel --force-resolved-versions --filter 'Performance|MarkdownTreeReuse'`
- **Result:** 32 tests in 10 suites passed, 6.3 s of test time (115 s including the Release build), exit 0. Includes the editor, editing-assist (E10), highlighting, JSON outline, Markdown parse, math rendering, export-sentinel and tree-reuse (#203 tripwire) suites.
- **Host:** macOS 26.5.1, arm64, Xcode 26.6, one run.
- **Raw artifact:** `run1.log.gz`.

## What this does and does not show
- These suites assert generous documented ceilings and a few strict budgets (e.g. an 8 ms main-actor gutter update). Passing in Release means those assertions hold; it is **not** a statement that the 50 ms Markdown keystroke budget is met at 1 MB. That budget is the known #203 gap (≈130 ms at 1 MB; owner disposition: restate as size-dependent, see `planning/CLOSURE_REGISTER.md` row H5). The `1 MB re-parse` test passes against its documented *ceiling*, not the 50 ms budget.
- Measured samples in the log: E10 assisted overhead 2.63 ms/decision on a 1 MB document; 100-equation math render 0.19 s; 10 MB Markdown re-parse baseline 2.8 s.
- Not covered: whole-app memory with representative mixed documents and 20 tabs (a separate E15 criterion), power/thermal behaviour, other hardware.
