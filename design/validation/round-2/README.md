# Round 2: small-size diagnosis and the next validation tranche

**Owner summary.** Round 1 (`../read-test/RESULTS.md`) is exploratory evidence: eight real people
were sent the stimuli instead of being run through the timed protocol, so it is not a formal D-023
result. Its findings still count as evidence. The 64 px mark read as M+T for 8 of 8, but 0 of 8
picked the 16 px microglyph in the line-up: all eight picked the same decoy, Soft. The automotive
trigger also fired (6 of 8). This folder diagnoses why and holds the **approved** round-2 kit, which
is the formal human gate. It **changes no production artwork, Figma asset or decision**.

**Approved by the owner on 2026-09-26:** the diagnosis, the derive-from-master correction rule and
the tranche A protocol. The 16 px line-up is the only formal small-size gate (at least 6 of 8). The
32 px line-up is diagnostic only, and its evidence carries into the Mac / Icon Composer validation.

- **Why Soft won:** at 16 px, Soft is the closest image to the big mark. It is the same shared-stem M+T
  ligature, and the test harness gave it the same 12° lean and glyph box. Our microglyph is 17–22%
  lighter than the master and breaks the ligature into two separate, thin letters. By an
  alignment-independent pixel match, Soft resembles the master more than our microglyph does.
- **The same drift affects the 32 px master**, which covers most Retina use. It is untested by people
  but measurably further from the master than Soft is.
- **Correction rule (approved; not yet applied to production):** re-derive both small drawings from the master's own proportions,
  keeping D-014's pixel rules. Candidates `R2-16` and `R2-32` match the master better than any decoy.
- **Next tests:** tranche A compares 8°, 10° and 12° with fresh, separate panels (D-021). Tranche B
  re-runs the line-up with only the target changed, at whichever lean tranche A keeps.

Details: [`DIAGNOSIS.md`](DIAGNOSIS.md) (evidence) and [`PROTOCOL.md`](PROTOCOL.md) (the tests,
with thresholds fixed before any data).

## Files

| File | What it is |
|---|---|
| `candidates.mjs` | Proposal geometry: the lean variants and the re-derived R2-16 and R2-32. Not production |
| `build.mjs` | Builds `stimuli/`, `stimuli.html` (facilitator page) and `lineup-key.json` |
| `measure.mjs` | Pixel-match measurements (`measurements.txt`) and the visual sheet `diagnosis.png` |
| `score.mjs` | Deterministic scoring for both tranches: `node score.mjs lean …` or `node score.mjs small …` |
| `responses-lean-template.csv`, `responses-small-template.csv` | Blank response sheets |
