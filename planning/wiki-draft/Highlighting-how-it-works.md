# How syntax highlighting works in MostlyText (and what we learnt)

*Draft for review. Plain English; numbers are measurements on one Mac (Apple M3 Pro) unless said otherwise. Last updated 2026-10-18.*

## The short version
Colouring your Markdown as you type is more work than it looks. For ordinary notes it is instant. For very large documents it can freeze typing for a noticeable moment, so above a size limit MostlyText **switches the colouring off for that document** and tells you so. Your text, editing, undo, search and saving are not affected.

## How it works
1. **A parser reads your text.** We use *tree-sitter*, a fast library that turns text into a tree: this is a heading, this is a list, this word is bold. Markdown needs **two passes**: one for the structure of blocks (headings, lists, code fences) and one for the formatting inside paragraphs (bold, italics, links, code). The second pass is the expensive one.
2. **Neon connects the parser to the editor.** It decides what to re-read when you type and which pieces on screen to recolour.
3. **The theme picks the colours**, and the text system draws them over your text without changing the text itself.

Each keystroke triggers a re-read so the colours stay right.

## What we learnt
- **Small documents are fine.** Under about 8,000 characters a keystroke costs a few milliseconds to a few tens of milliseconds, well inside the 50 ms we aim for.
- **Cost grows faster than size.** Measured on a dense Markdown test document, one keystroke blocks typing for roughly 150 ms at 64 KB, about 1.9 to 2.2 seconds at 256 KB, and several seconds around 1 MB. Doubling the document more than doubles the delay.
- **The inline pass is the cost.** At 256 KB almost all of it is re-reading the formatting inside paragraphs. The parser reuses almost nothing from the previous read, so it effectively starts over on every keystroke.
- **Pasting a huge block is worse.** Without the size limit, pasting 1 MB freezes the app for tens of seconds, mostly while the colours are applied piece by piece.
- **Some bugs are in the libraries we use.** After certain edits (replacing a selection, deleting a block, several edits in one instant) the colours can end up different from what a fresh open would show. We traced this to the editor library's bookkeeping, and to one place in the parser's range handling. We reproduced these problems and tried small fixes on an experimental branch; none is adopted.

## What we decided
- **A size limit.** Above **8,192** characters (technically UTF-16 code units) the colouring is turned off for that document; it comes back automatically once the document is back under about 6,144 and you pause for 2 seconds. The gap between the two numbers stops it flickering on and off near the limit.
- **Why not simply optimise?** We investigated. One small parser change makes one part flatter, and a one-line idea in the parser cut one big cost by about 3x in an experiment, but none of the ideas brings large documents under the 50 ms goal, because every keystroke still re-reads the whole formatting layer. The real fix is a larger design change (reading paragraph by paragraph), which depends on other projects and has not been built.
- **We tested the limit's behaviour, not just the idea.** Typing across the limit, pasting across it, undo and redo, switching tabs and closing a document leave your text intact. One known small cost remains: if you paste a very large block within a few milliseconds of opening or editing, the old colouring work still finishes once, about a quarter of a second at worst in tests (about 25 ms extra in the measured case), and then does nothing.

## Trade-offs, honestly
| Choice | Gain | Cost |
|---|---|---|
| Turn colouring off above 8,192 characters | Typing stays responsive | Large documents are uncoloured. The Preview and Outline views are separate and are **not** changed by this |
| Keep the limit low and conservative | Safe on slower Macs and dense text | Some mid-sized documents lose colouring that would have been fine |
| Not adopting library patches yet | No risk from unreviewed changes in shared libraries | The colour-after-edit bugs remain for documents under the limit |

## What is not finished
Full colouring of very large documents; the library fixes; native testing with a Chinese input method (written, not yet run because the UI test runner needs someone at the Mac). None of this blocks normal use under the limit.

## Words used above
*Parser*: reads text and builds a structure. *Tree-sitter*: the parser library. *Neon*: the editor library that connects it to the screen. *UTF-16 code unit*: how the text system counts characters (most characters are one; some emoji are two).
