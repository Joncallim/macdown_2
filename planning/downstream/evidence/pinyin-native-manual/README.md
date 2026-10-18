# Native Simplified Pinyin session (hand-driven), 2026-10-18

**What this is:** a manual, OS-level key-event session in the Debug app (`MacDown2.app`, built from `integration-final` content at `0d877446`, then from the fix below) with the macOS *Pinyin – Simplified* input source (`com.apple.inputmethod.SCIM.ITABC`) selected, on an Apple M3 Pro, macOS 26.5.1. Keys were sent through the computer-use tooling to the frontmost app, so they went through the real input method and its candidate window. **It is not the automated XCUITest suite**, which does not work with an input method (see below) and remains unmerged on `pinyin-ui-tests`.

## Results
| Check | Result |
|---|---|
| Compose "ni", candidate window shown; space commits the first candidate | pass: 你 committed; "hao"+space then gave 你好 (2 characters, preview matches) |
| Escape during a composition ("ni" then Escape) | pass: pre-edit removed, document unchanged (still 你好) |
| Undo, undo, redo, redo | pass: first undo removed the committed text, redo restored 你好; a following composition ("shijie"+space) committed (时节): the stale-model class (#439) did not recur |
| 8,190-character document, compose "nihaoma" (pre-edit takes the count to 8,199, over the 8,192 limit) | pass: status bar showed "Highlighting reduced" and 8,199 characters while composing; no text lost |
| Commit the candidate across the limit | pass: line 147 = 你好吗, 8,193 characters, earlier 146 lines intact, highlighting reduced |
| Undo / redo across the limit | pass: undo -> 8,190 characters, redo -> 8,193, document intact; note stayed (8,190 is above the 6,144 restore threshold) |
| Undo, compose "nihaoma", Escape | pass: back to exactly 8,190 characters |
| Paste 9,000 characters (crossing at once) | pass: reduced note shown |
| Replace everything with a 46-character document (restore) | **FAILED before the fix:** note disappeared but the text stayed uncoloured until the next edit (reproduced 3 times; TextKit held 4 coloured runs; confirmed by logging). **Fixed** by the repaint in PR #488 (`15119add`); verified live with the final code: colours returned on their own |

## Not covered
Other input methods (Traditional, Wubi, Shuangpin, Japanese, Korean), candidate-window mouse interaction, and long compositions with the highlighter mid-restore. Screenshots were taken during the session but are not committed.

## Why the automated XCUITest suite did not work
Runs 4-10 (`pinyin-ui-tests`, `4cc7a262`): all skipped when Pinyin was not enabled (run 4); then failures. While a composition panel is open XCUITest reports it as an interrupting `Dialog`, `typeText` loses keyboard focus or hangs, raw `CGEvent` posting from the runner is dropped (`AXIsProcessTrusted()` false in the runner), and app-level keys did not commit the candidate. The app itself was idle (sampled), so this is the harness, not the editor.
