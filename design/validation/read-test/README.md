# Blind read test for the Slant mark

**Owner summary.** This package checks whether people who have never seen the
mark read M and T in it, and whether they can pick it out at 16 px. It also
records what it reminds them of, especially cars or motorsport. It is the
perceptual gate in D-018/D-019, with exact rules in D-022 as amended by D-023.
Participants never see the product name, the wordmark or any design rationale.
The formal test needs **exactly 8 valid participants**, seen one at a time,
about 5 minutes each.

## What's in this folder

| File | Purpose |
|---|---|
| `stimuli.html` | The only thing participants see. Open it in a browser, full screen, at 100% zoom. |
| `stimuli/` | 16 px line-up glyphs: `glyph-T.png` is the target, `glyph-d1`–`d4.png` are decoys. |
| `lineup-key.json` | The correct line-up letter per participant. **Facilitator only; never on screen.** |
| `responses-template.csv` | Copy to `responses.csv` and fill in verbatim. |
| `score.mjs` | `node score.mjs responses.csv` prints PASS / HOLD / FAIL / INCOMPLETE against D-019, D-021, D-022 and D-023. |
| `build.mjs` | Rebuilds the stimuli from the checked-in mark sources. Not needed to run a session. |

## Rules for the facilitator

- Never say "MostlyText", "Markdown", "text editor", "M", "T", "letters",
  "logo for", "slant", "italic" or "car" before the participant answers.
- Don't show this README, the design boards or the repository.
- Write answers down **verbatim**, including hesitations ("uh… an M?"). Don't
  summarise or correct them.
- Give no feedback: no "good", no "interesting", no nodding towards an answer.
  Say "thanks" and move on.
- Recruit people who haven't seen any of the design work. Colleagues who have
  seen the boards are not valid participants.
- Use the same screen for everyone if you can, and note the screen type (e.g.
  "MacBook Air Retina") in the `screen` column. The 16 px line-up is rendered
  with true 1× pixels, enlarged by nearest-neighbour on Retina screens so every
  participant sees the same pixels.

## Stimuli (fixed)

| Code | What the participant sees | Size |
|---|---|---|
| S1 | The mark alone, black on white | 64 px |
| S2 | The app icon (light, two-tone) | 128 px |
| S3 | A plain website header with the mark and neutral links (Features, Help, Download) | mark 40 px |
| L-P1 … L-P8 | Five 16 px glyphs labelled A–E: the target and four decoys, all leaning 12°. Position rotates per participant | 16 px |

The wordmark lockup is deliberately **not** a stimulus: it spells the name and
would give away the letters.

The decoys are other two-letter constructions from the rejected exploration
rounds (Crown, Gate, Caret, Soft). Each gets the same 12° lean and glyph box as
the target, so neither "the slanted one" nor size identifies it. Soft (d4) is a
deliberately close lure.

## Procedure and exact wording

Open `stimuli.html`, which starts on a facilitator menu. Press **1**, **2** or
**3** to show S1–S3 for exactly 5 seconds, after which the screen blanks
automatically. Press **L** then the participant number (**1**–**8**) for that
participant's line-up. **Esc** returns to the menu. Turn the screen towards the
participant only after pressing the key.

Say at the start, word for word:

> "I'm going to show you a few images very briefly. There are no right or
> wrong answers. I just want your first impressions, in your own words."

**Step 1: S1 (5 s).** Once the screen blanks, ask in this order:
1. "What letters, if any, did you see?" → `s1_letters`
2. "What did it remind you of?" → `s1_reminds`
3. "What kind of product or company might use it?" → `s1_product`

**Step 2: S2 (5 s).** Then ask:
1. "What letters, if any, did you see?" → `s2_letters`
2. "What did it remind you of?" → `s2_reminds`

**Step 3: S3 (5 s).** Then ask:
1. "What did that remind you of?" → `s3_reminds`

**Step 4: line-up (no time limit, but first answer counts).** Show `L-P<n>` for
this participant and say:

> "One of these tiny symbols is the same symbol you saw earlier. Which one:
> A, B, C, D or E?"

Record the letter in `lineup_choice`. Then ask "How sure are you, from 1, a
guess, to 3, certain?" and record the answer in `lineup_confidence`.

Finish with: "Thanks, that's all." Only after the session is over may you
explain what it was for.

## Recording

- One row per participant in `responses.csv`, with IDs P1–P8 in the order you
  run them. The ID decides which line-up is shown.
- `valid`: `Y` by default. Set `N` if the session was compromised (for example
  the person had seen the design work, the name was mentioned, or the
  stimulus was shown for the wrong time), and say why in `notes`. Replace an
  invalid participant with a new person, reusing the same ID and line-up, so
  the test still reaches 8 valid participants.
- `letters_override`: leave blank. Only enter `Y` or `N` when an **S1** answer is
  genuinely ambiguous and the scorer's letter rule would misread it (for
  example "looks like a M-T thing but backwards"). Note why in `notes`.
- Keep `responses.csv` alongside this README when committing results. It
  contains no personal data beyond the participant IDs.

## Scoring (deterministic)

`node score.mjs responses.csv` applies these rules. Thresholds are fixed and
don't scale with the number of participants.

| Measure | Rule | Pass |
|---|---|---|
| **Gate 1: logo-scale reading** | **S1 only** (the first exposure, the monochrome 64 px mark): `s1_letters` names both M and T (as "M and T", "MT", "TM", "em/tee" etc.). `letters_override` wins when set | **at least 6 of 8**. 7 of 8 is the target |
| **Gate 2: 16 px recognition** | `lineup_choice` equals the participant's key letter | **at least 6 of 8** (chance is 1 in 5) |
| Automotive trigger | Any answer mentions BMW, car, motor, racing, sport, speed or similar (full list in `score.mjs`) | fewer than 3 participants |
| Diagnostic only | S2 letters and all S2/S3 associations are reported but **never counted towards Gate 1**. They can't rescue a failed S1 | — |

The result is one of:
- **PASS:** both gates pass and the trigger doesn't fire.
- **HOLD:** both gates pass, but 3 or more people made automotive
  associations. Run the 8°/10°/12° comparison in D-021.
- **FAIL:** a gate was missed.
- **INCOMPLETE:** anything other than exactly 8 valid participants. The
  scorer also prints a provisional reading, which is not a result.

The keyword check only automates the automotive trigger. Read every verbatim
association by hand as well, and flag any other association that 3 or more
people share.

## Known limits

- The target microglyph is hand-tuned for 16 px, while the decoys are scaled
  masters. It may look slightly crisper, which is a small bias in its favour.
- Showing S1 first primes S2 and S3. That is why Gate 1 uses S1 alone, and why
  S2 and S3 are diagnostic only.
- Eight people is a screen for obvious problems, not a statistical study.
