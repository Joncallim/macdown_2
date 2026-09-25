# MostlyText Slant human read-test evidence

Status: **INCOMPLETE — the formal D-023 gate cannot yet be closed.**

Eight anonymised reviewer records were supplied and are preserved under `raw/`.
They contain S1, S2 and S3 responses, but **none includes the required 16 px five-glyph lineup choice or confidence**. The fixed D-023 protocol requires that second gate, so `score.mjs` has deliberately not been run on these incomplete rows.

## What the supplied evidence does establish

- **S1 M+T reading: 8/8.** Every reviewer identified both M and T on the first monochrome mark. This exceeds the D-023 Gate 1 threshold of 6/8.
- **S2/S3:** diagnostic only. Reviewers consistently interpreted the coloured tile and header as software/app/product contexts; these observations do not contribute to Gate 1.
- **Automotive / motorsport trigger: already fired.** Six reviewers (P2, P4, P5, P6, P7, P8) independently used sports, motorsport, racing, automotive, speed/performance, esports, or closely related language in their supplied associations. This exceeds the D-021/D-023 trigger of 3 participants.
- **16 px recognition gate: not recorded.** No reviewer file includes an A–E lineup choice or confidence value.

## Consequence under the frozen rules

The evidence is **not a formal PASS** yet because Gate 2 is missing. If the 16 px recognition gate later reaches 6/8, the existing automotive/motorsport associations mean the outcome is **HOLD**, not PASS, and the prepared 8° / 10° / 12° follow-up comparison in D-021 must be run before public freeze.

No thresholds or rules were changed after seeing the responses.

## Next action

Collect from the same eight participants, if practical:

1. their assigned P1–P8 five-glyph lineup;
2. first A–E choice;
3. confidence from 1 (guess) to 3 (certain).

Then fill `lineup_choice` and `lineup_confidence` in `responses.csv` and run:

```bash
node score.mjs responses.csv | tee score.txt
```

If the original participants cannot be re-contacted, rerun the complete fixed protocol with a fresh panel rather than inventing or retrospectively inferring lineup answers.
