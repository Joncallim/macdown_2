# Round-2 protocol (proposed; thresholds fixed before any data)

Two tranches. **Run A first**, because the lean it keeps decides the geometry B tests. Nothing here
changes D-019 to D-023. The pass counts are the same 6 of 8 and the automotive trigger is the same 3.

## Who can take part

- **People only.** A facilitator runs every session live on a real screen. Responses from AI models,
  or from people sent the image files, are invalid.
- **Fresh participants.** Nobody from round 1, nobody who has seen the design work, and nobody takes
  part in more than one panel. Record anyone excluded with `valid = N` and replace them.
- **Exactly 8 valid participants per panel.** Any other count is INCOMPLETE.
- **Screen:** record the screen in `screen`. The 16 px and 32 px line-ups are shown as true pixels
  (`image-rendering: pixelated`) at 100% zoom.

## Tranche A: lean comparison (D-021)

**Panels:** three independent panels of 8: 8° (`A-L8`), 10° (`A-L10`) and 12° (`A-L12`). Each person
sees **one angle only**, once, as a 64 px monochrome mark for 5 seconds (first exposure). The stimuli
are the production construction with only the angle changed; `lean-12` is pixel-identical to
`slant-master.svg`.

**Questions** (after the image is gone, in this order, never prompting M or T): "What letters, if
any, did you see?", "What does it remind you of?", "What kind of product or company might use it?".
Record every answer word for word.

**Per-panel result** (`node score.mjs lean responses-lean.csv`):
- PASS: at least 6 of 8 name both M and T, **and** fewer than 3 automotive associations.
- HOLD: M and T pass, but 3 or more automotive associations.
- FAIL: fewer than 6 of 8 name M and T.

Automotive associations are counted with round 1's exact keyword list. A narrower cars-or-motorsport
count is reported as a diagnostic only.

**Decision rule, fixed now:** keep the **largest** angle whose panel passes. If 12° passes this fresh
panel, the lean stays at 12°. If no angle passes, stop and report: no angle outside 8–12° is chosen
without an owner decision. A lean change would also move the wordmark's extra slant (D-012, D-015),
the lockup, the 32/16 px drawings and the icon sources. None of that happens before the decision is
recorded.

## Tranche B: small-size recognition, fresh panel

Run it at the lean tranche A keeps. At 12° the stimuli are already built. At another angle, rebuild
`R2-16`/`R2-32` with the same `derive()` rule.

**Sequence per participant:**
1. **S1:** the 64 px mark for 5 seconds (key S), then the three S1 questions. This is a diagnostic
   replication.
2. **16 px line-up:** keys L + participant number. "Which of these five is the same mark you saw
   first?" The first answer counts.
3. **32 px line-up:** keys K + participant number. Same question.

The **decoys and positions are exactly round 1's**, including Soft (d4), using the same fitting rule.
The target position rotates per participant by the same order. Only the target changes, to R2-16 and
R2-32, so the result is directly comparable with round 1. Keeping Soft makes this the hard version of
the test: the candidate has to beat the decoy that won round 1.

**Result** (`node score.mjs small responses-small.csv`):
- **16 px gate:** at least 6 of 8 pick the target (unchanged from D-022/D-023).
- **32 px:** at least 6 of 8. **Owner decision needed before the test runs:** make this a formal gate
  (proposed), or keep it diagnostic.

## If tranche B passes

Then propose, as new decisions (none are recorded yet):
1. Replace `slant-16.svg`, `slant-32.svg` and the icon-16 inner glyph with drawings from the `derive()`
   rule. The icon glyph is validated at the Mac icon gate.
2. Update the Figma 02/04/05 components and the production outlines. The master and the Figma master
   components don't change unless tranche A moves the lean.

If B fails, stop and report the evidence. Don't iterate candidates against the same participants.

## Running it

```sh
cd design/validation/round-2
node build.mjs          # stimuli/, stimuli.html, lineup-key.json
node measure.mjs        # measurements.txt, diagnosis.png
open stimuli.html       # facilitator page; keys A+8/0/2, S, L+1–8, K+1–8, Esc
```

`lineup-key.json` is for the facilitator only and must never be on screen.
