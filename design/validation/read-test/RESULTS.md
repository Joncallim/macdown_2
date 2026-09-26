# MostlyText Slant human read-test result

Date recorded: 2026-09-26
Protocol: D-023
Participants: 8 valid participants

## Formal result: FAIL

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

## Evidence

- Raw anonymised reviewer responses: `raw/Reviewer 1.txt` through `raw/Reviewer 8.txt`
- Structured responses: `responses.csv`
- Deterministic scorer output: `score.txt`

Lineup confidence values were not recorded; D-023 does not use confidence for the pass/fail calculation.

## Consequence under the frozen rules

Do **not** close the human gate and do **not** change the thresholds after seeing this result.

The identity requires reconciliation before public freeze. Two separate findings now need investigation:

1. **Small-size identity drift:** redesign or re-evaluate the ≤17 px microglyph so it is recognisable as the large Slant mark, then run a fresh recognition test rather than reusing these exposed participants.
2. **Automotive/motorsport association:** per D-021, compare 8°, 10° and 12° with a fresh panel and keep as much lean as passes.

No production geometry has been changed by recording these results.
