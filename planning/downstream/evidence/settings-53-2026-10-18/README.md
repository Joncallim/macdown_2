# Settings compatibility and legacy-key reconciliation

## Owner outcome

The settings decoder now distinguishes an absent status-bar preference from an
explicitly malformed value. Older valid preferences still retain their font,
indentation and editing choices; an explicit JSON `null` is rejected instead of
being accepted as the default Boolean. This is a bounded decode correction,
not a completed legacy preference importer.

The existing legacy table is now backed by a machine-readable declaration record
and a read-only checker. It covers 52 stored, four calculated and two transient
properties without guessing corrected spellings or treating transient file-open
requests as importable preferences. The six possible current settings mappings
remain candidates until their conversions and precedence are proved.

An isolated probe also establishes why #53 cannot close yet: ordinary saves can
replace an unsupported future schema; only the first unreadable generation is
backed up. A second generation can be lost, and non-Data objects are neither
reported nor backed up. The planned shared protected writer and recovery policy
remain necessary. No new persistence policy was invented in this slice.

## Baseline and bounded contract

Work began on clean `fix/ci-timing-contracts` at
`d3cc8883a08df02a9a98165b1833ca950948dc5d`, with master
`4aa46bfa6b91bf1c1d218b9b1f67480312f66396`. The live #53 body and all comments,
the existing handoff, epic standard and release-hardening contract were read
before implementation. The master/integration settings diff was inspected.
Legacy source was read as existing Git objects at
`3e2a2bf101c215c143bf00d9f857965f0ee82487`; no legacy app was instantiated.

Allowed changes were the reproduced single-field decode defect, isolated test
fixtures and non-runtime coverage/evidence. Import execution, new schema or
write protocols, theme APIs, parser behavior and product preferences are outside
this bounded slice. The broader write-protection mismatch triggers the existing
architecture stop rule: complete its admission/recovery contract before changing
setter behavior or adding migration writers. Owner review remains required.

## Reproduction and discriminating checks

On unchanged baseline production source, the new parameterized test failed only
for `showsStatusBar: null`: it returned the nondefault editor values with
`showsStatusBar == true` and reported no unreadable domain. Numeric zero, a
string, an array and an object were already rejected. The corrected decoder
checks key presence before requiring a Boolean. The same cases then pass,
alongside explicit `false`, `true` and the existing absent-field fixture.

The first attempted command never reached tests: SwiftPM could not apply its
manifest sandbox inside the outer sandbox. Its failure log is retained. A
permitted run of the unchanged source produced the actual failing expectations;
this is not a pass-on-retry argument. Dependency locks were enforced throughout.

The affected fixture helpers now delete their own UUID-named persistent domains
instead of removing a suite from the standard search list. Detector tests always
pass their explicit fixture suite; no test invokes the real legacy-domain default.
No Jonathan preference values were read or modified.

The baseline write probe compiled exact committed AppSettings files with Swift 6,
strict concurrency and warnings as errors. It used only synthetic future JSON
and non-Data values in one unique suite, verified removal of that suite and
reported these observations:

| Observation | Baseline result |
| --- | --- |
| Reading a future-version blob reports it and leaves primary bytes untouched | True |
| An ordinary save replaces that future primary blob | True |
| The first future generation survives in the one-time backup | True |
| A second future generation survives a later save anywhere in the fixture domain | **False** |
| A non-Data object is reported as unreadable | **False** |
| That non-Data object survives ordinary replacement | **False** |

These observations prove the stated schedules, not every migration or race
scenario. The older test names implied no future-blob rewrite and repeated-launch
idempotence, but asserted only the first backup and repeated reads. They now name
those actual checks. Their assertions remain unchanged; no failing requirement
was weakened.

The [probe source](SettingsWriteProbe.swift) and
[observations/source hashes](write-preservation-probe.json) are retained. To
reproduce, read the AppSettings `.swift` files from the named Git commit into a
temporary directory, compile those files with this probe using
`swiftc -swift-version 6 -strict-concurrency=complete -warnings-as-errors -parse-as-library`,
then execute the resulting diagnostic. Its exit zero means the probe ran and
cleaned its fixture, not that the write-protection requirements passed.

## Legacy declaration coverage

The [disposition record](../../legacy-preference-dispositions.json) pins the
header and implementation hashes. Four parser capability rows now reflect
current E22 behavior (tables, fenced code, strikethrough and task lists are
unconditional); extended bare autolinks and footnotes are not supported. There
is no new parser switch. Font and five editing-assist fields have destination
candidates, not tested conversions. Word-count visibility cannot be silently
mapped to the whole status bar.

Run from the repository root, with the pinned Git objects already available:

```sh
python3 planning/downstream/tools/check_legacy_preference_map.py
python3 -m unittest discover -s planning/downstream/tools -p 'test_legacy_preference_map.py'
```

For a shallow clone or clean source archive, supply the captured upstream files
with `--header /path/MPPreferences.h --implementation /path/MPPreferences.m`;
their digests must match. The checker performs no fetch or preference access.
Negative controls reject missing/duplicate/new keys, an invented correction of
the legacy spelling, wrong calculated/transient classifications, stale
destination symbols, changed source bytes and a false migration-completion claim.
This standalone checker is not yet a hosted CI requirement and does not validate
PAPreferences aliases or keys found in a real user's domain.

## Remaining gates and next independent work

#53 still requires complete conversion semantics, protected destination writes,
version/provenance admission, precedence, consent, idempotence, restart recovery,
final E23 theme destinations and the real isolated-account E17 migration path.
Live apply and native UI behavior have no new manual evidence from this slice.
The current setter interface and first-backup behavior need explicit architecture
reconciliation before broad migration implementation.

The previous Release parser result **484.814584/400 ms** and editing-assist result
**56.881709/50 ms** remain unresolved. No performance suite was rerun. The 8,192
UTF-16 highlighting fallback, production pins, dependency experiment isolation
and eight compliance release failures remain unchanged. Nothing was pushed,
merged, published, signed, notarised or changed in an external issue.

The next independent intake can be #121's documented preview-load cancellation
and stale-request contract: reconcile it with the current scheme handler and
construct one deterministic isolated request-lifetime reproduction before
changing architecture. This recommendation is not implementation or native
WebKit proof. Owner acceptance and all external-state holds remain pending.

Raw evidence:
`/Users/jonathanlim/GitHub/_cleanup-archive/settings-53-d3cc8883-2026-10-18/`.
Final independent review and exact-head validation will be recorded alongside
this document before the checkpoint is handed off.
