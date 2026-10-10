# Issue #88 — Reliable UI execution and final artifact evidence

## Owner summary

The UI suite must prove that real user actions reach the app and preserve the expected state. Correct stale tests, but never weaken the behavior being tested or label a skipped/headless path as passed. Provide one repeatable interactive macOS verification lane so PDF, Finder, accessibility and final-release checks stop becoming disconnected manual notes.

Reviewed baseline: `83a79a4572e23a781b2cf370dd2b407fe7409d09`, 2026-09-24. This is downstream test architecture, not a request to interrupt E22 or rerun Claude's current CI. The lane may be prepared later, but final execution is against the completed E22/E23/debt baseline.

## Current evidence, not the original failure count

Read both issue comments, CI, EditingAssistsUITests, WindowController+Close and PDFExportAdapterTests. PR #90 reduced the original 15/30 failures to 3/30 in a genuinely executed historical run. The remaining cases are native conflict-close NSAlert event delivery, native tab-switch command state, and a sidebar-focus test clicking static placeholder text. The later 2026-09-21 comment explicitly removes the earlier environment waiver. Do not reopen twelve already-fixed paths or assume today's suite still contains only thirty tests.

Current CI genuinely runs package tests and non-UI MacDown2Tests. MacDown2UITests is build-only. The PDF adapter tests are unconditionally disabled with instructions to edit source before running. A green CI build therefore cannot establish these UI/PDF release conditions.

## Harness ownership and trust

Add a repository-owned interactive verification script, Xcode test plan and machine-readable evidence report. Keep hosted CI's existing checks; add a separate explicitly invoked interactive lane rather than making headless runners claim GUI support. A dedicated logged-in macOS 26 test account/machine must have verified automation/accessibility permissions, an unlocked usable WindowServer session, known keyboard input source, recorded display/scaling, and no competing GUI driver.

The harness preflight verifies those facts through a harmless positive-control app interaction, then verifies the exact app path, bundle ID, executable/CDHash and source/build identity. Permission failure is BLOCKED with evidence and no product patch. Do not use a root runner, reset the owner's TCC database, grant global permissions, expose signing keys to test code, or run untrusted fork PR code in this privileged GUI session. Run only the operator-selected reviewed ref/artifact.

Use an isolated temporary fixture root and test-account preferences/session state. Never point -sessionDir or recovery fixtures at the owner's real data. Cleanup only roots created and tagged by the current run; failure artifacts live outside that cleanup root. Serialize UI tests and ensure only the harness-owned app process is terminated. Do not kill unrelated WebKit, Finder, git or system processes.

## Two kinds of proof

Engineering lane: build the app/test targets from an exact source SHA using XcodeGen, strict concurrency and the documented coverage workaround. Execute UI tests with isolated fixtures and appropriate test hooks. Record these as source-linked engineering evidence, not proof of the final notarized binary.

Artifact lane: install/open the exact signed candidate selected by #18, launch it as a normal user and drive public UI without rebuilding/re-signing it or enabling alternate product behavior. The UI driver must attach to the verified bundle/process; confirm its executable path so a Debug build with the same ID cannot be tested accidentally. Source/test-runner hashes and candidate hashes are recorded separately. Finder/Quick Look/Gatekeeper/export/upgrade and final critical journeys use this lane. A test-only app configuration cannot satisfy an exact-artifact claim.

## Fix the three remaining scenarios

**Sidebar focus.** Supply a real nonempty folder fixture or a populated outline and focus a genuinely focusable row/control. Assert that the expected control actually became first responder/focused before testing command eligibility. Do not change static placeholder text into a focusable production control just to satisfy the old test. Open/query the Format menu afresh after the transition rather than trusting an old lazy menu snapshot. Return to the editor and verify both command enablement and one actual formatting mutation with correct undo.

**Native tab switch.** Give both tabs unique visible document identities and distinct content/format, activate the origin and issue the native switch. Wait for the selected document/window identity to change before checking the newly queried menu item. An event synthesis log is not this assertion. If Ctrl+Tab is demonstrably unreliable in the test host, use the real native Window-menu action that performs tab switching, as the issue permits, and separately record the keyboard journey on the interactive artifact. Do not call WindowCoordinator's selection method directly or rename the test to hide that no native switch occurred. Recheck the expected formatting behavior against completed E22 rather than preserving a stale menu expectation.

**Conflict-close alert.** Produce a real on-disk conflict, capture local/external hashes, open the native close sheet for that exact window and locate a unique enabled/hittable 'Use Disk Version and Close' action within it. Bring the correct modal session forward. Invoke the real button or supported keyboard/default action, then assert sheet completion, correct window closure and unchanged external bytes. Selecting a button that merely exists is insufficient. Engineering instrumentation may trace callback entry; the final artifact lane must prove outcome without bypassing the NSAlert completion handler. If native action delivery fails the positive control too, repair/identify the harness environment rather than rewriting correct close logic.

## Deterministic test mechanics

Use bounded condition waits for specific observable changes: selected tab identity, focused element, sheet transition, expected editor value, disk/recovery state. Keep timeouts as failure bounds, not sleep durations pretending work completed. Capture accessibility hierarchy, screenshot, action trace, actual assertion state and app/system logs on failure. Distinguish a wrong AX query from an actual product state error; preserve PR #90's identifier-containment fixes.

Replace try?-created critical fixtures with throwing/required setup so a missing file cannot masquerade as a focus or parser bug. File names include unique run IDs; resolve the intended window instead of app.windows.firstMatch when multiple windows exist. Avoid stale XCUIElement/menu snapshots across tab changes. Test isolation includes launch arguments, preferences, process lifetime and cleanup after failure.

For timing-sensitive non-UI coordination tests encountered by the lane, prefer controllable clocks/continuations and state barriers. One same-SHA rerun may diagnose nondeterminism, but 'rerun until green' never closes a defect. Keep all failed attempts in evidence and investigate repeated failures.

## PDF and full-suite execution

Replace PDF tests' unconditional disabled traits with an explicit supported interactive-test condition/test-plan configuration. The default headless suite may exclude the GUI-only cases honestly, but the release lane must fail if its selected PDF cases are skipped or absent. Do not require manual source edits to remove .disabled before every release.

Enumerate the current test inventory at run time and compare discovered/executed/passed/skipped counts against a checked-in critical-behavior manifest. Include existing editing, format/preview, tab lifecycle, external-file and diagram flows, then add completed E22 and E23 theme/Quick Look/identity journeys. A renamed test needs a traceable replacement entry; a deleted test cannot reduce the required behavior set silently.

Exercise the real #118 menu/save-panel/PDF print pipeline. Save the PDF/HTML outputs outside the fixture cleanup root, validate their bytes/text/page geometry, and record independent visual inspection. VoiceOver and Finder-specific observations receive named manual evidence entries where they cannot be truthfully automated. They remain required, not silently marked by unit tests.

## Evidence record and pass rules

Each run records source SHA, test-driver SHA, app path/hash/signature/build configuration, OS/SDK/Xcode versions, host characteristics, fixture hashes, explicit test selection, result bundle path/hash, actual counts and per-case outcome. Preserve failed/blocked/skipped records. Screenshots and logs must omit unrelated private windows/content.

Terminal outcomes are PASS, FAIL, BLOCKED or NOT_RUN. PASS requires actual action/outcome assertions and all critical cases accounted for. Build-only, skipped, synthesized-only and environment-blocked are not PASS. Focus/native-modal repairs require repeated targeted clean runs plus one complete current critical suite; the final release artifact receives its own public-UI verification. Exact numbers are produced by execution, not copied from the historical 30-test run.

## Implementation order and allowed files

1. Add the script/test plan/critical-case manifest and positive-control preflight. No CI rerun or environment mutation is part of this documentation work.
2. Repair the three stale/delivery scenarios with fixture and observation changes first; change production code only when an observed state defect is established.
3. Integrate conditional PDF execution and assertion of non-skipped release cases.
4. Incorporate post-E22/E23 test inventory, execute engineering and final-artifact lanes, and publish immutable result bundles to #115's ledger.

Allowed areas: test infrastructure, relevant UITests/PDF tests, test plans/project declarations, evidence docs; narrow proven AX/focus defects only when necessary. Stop on data loss, wrong-window targeting, unverified candidate identity, unsafe permission changes or inability to exercise a critical public behavior. No blanket waiver and no removal of a critical assertion.

## Self-review and definition of done

Review corrected the obsolete 15-failure count, the superseded environment waiver, static text as a fake focus target, immediate assertions after event injection, accidental Debug-app testing, a headless CI green mislabelled as UI proof, and unconditional PDF skips. It also separates necessary engineering hooks from final-artifact evidence.

#88 closes when the three paths and the complete current critical suite have genuine successful evidence on the supported interactive environment, with equivalent traceable replacements for stale tests. This architecture has not run those tests or changed the owner's machine.
