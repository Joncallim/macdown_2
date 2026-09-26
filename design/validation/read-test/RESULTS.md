# MostlyText Slant human read-test: round 1 (exploratory)

Date recorded: 2026-09-26
Protocol intended: D-023 (not administered as specified; see the classification below)
Participants: 8 valid participants

## Classification: exploratory evidence, not a formal D-023 result

*Reclassified by the owner on 2026-09-26.* The eight reviewers were real people, but they were **sent
the stimuli**. They were not run through the timed facilitator protocol (5-second first exposure,
blank screen, live questions, and the 16 px line-up shown as true pixels on a facilitator screen).
Round 1 is therefore **protocol-noncompliant exploratory evidence**. It is neither a formal D-023 PASS
nor a formal D-023 FAIL, and gate 3 (the human read test) remains open.

This correction concerns how the test was administered, not its thresholds, which are unchanged. All
raw data, the scored output and the findings below are preserved as recorded. The findings still
direct the next round:

- The 16 px line-up choices (0 of 8 picked the target; all 8 picked Soft) are diagnosed in
  `../round-2/DIAGNOSIS.md` as a real small-size identity drift. The correction rule and a fresh,
  facilitated test are in `../round-2/`.
- The automotive associations (6 of 8 on the round-1 keyword list; 4 of 8 counting only cars and
  motorsport) justify running the D-021 8°/10°/12° comparison as round-2 tranche A.

The formal human gate is round 2, run to `../round-2/PROTOCOL.md`.

## Original recorded reading (preserved; superseded as a formal verdict by the classification above)

### Scored reading: FAIL

- **Gate 1 — S1 first-exposure M+T reading:** 8 / 8 — PASS.
- **Gate 2 — 16 px five-glyph recognition:** 0 / 8 — FAIL.
- **Automotive / motorsport association trigger:** 6 / 8 — TRIGGERED.

The eight lineup choices supplied by the owner were:

- P1 E (key C)
- P2 C (key A)
- P3 A (key E)
- P4 D (key B)
- P5 B (key D)
- P6 A (key B)
- P7 C (key E)
- P8 B (key A)

Every participant selected the **Soft (d4) decoy**, not the 16 px Slant microglyph. This is not random scatter: the target position rotated between participants, while the selected underlying decoy stayed the same. The result therefore indicates that the current 16 px microglyph does not preserve the same visual identity as the large Slant mark strongly enough for the fixed recognition test.

The automotive/motorsport trigger also independently fired: six participants used sports, motorsport, racing, automotive, speed/performance, esports, or closely related language in their unprompted responses.

### Evidence

- Raw anonymised reviewer responses: `raw/Reviewer 1.txt` through `raw/Reviewer 8.txt`
- Structured responses: `responses.csv`
- Deterministic scorer output: `score.txt`

Lineup confidence values were not recorded; D-023 does not use confidence for the pass/fail calculation.

### Consequence as originally recorded

Do **not** close the human gate and do **not** change the thresholds after seeing this result.

The identity requires reconciliation before public freeze. Two separate findings now need investigation:

1. **Small-size identity drift:** redesign or re-evaluate the ≤17 px microglyph so it is recognisable as the large Slant mark, then run a fresh recognition test rather than reusing these exposed participants.
2. **Automotive/motorsport association:** per D-021, compare 8°, 10° and 12° with a fresh panel and keep as much lean as passes.

No production geometry has been changed by recording these results.
