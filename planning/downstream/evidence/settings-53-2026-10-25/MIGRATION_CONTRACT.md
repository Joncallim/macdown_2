# #53 legacy-settings disposition and migration test contract

## Owner summary

This is the implementation-ready boundary for importing original MacDown
preferences into MostlyText. It preserves a user's intentional MostlyText
choices, never treats a legacy key as permission to enable a different feature,
and leaves the original domain unchanged. It is deliberately a contract and
test plan, not a migration implementation or an authorization to inspect user
preferences.

The source-backed declaration map is
[`legacy-preference-dispositions.json`](../../legacy-preference-dispositions.json).
It is exhaustive for the pinned `MPPreferences.h` / `.m` source at
`3e2a2bf101c215c143bf00d9f857965f0ee82487`: 52 stored, four calculated and
two transient declarations. Its checker verifies source hashes, exact legacy
spellings (including `supressesUntitledDocumentOnLaunch` and
`extensionStrikethough`), declaration kind and every disposition. This contract
does not infer PAPreferences aliases or keys absent from that source.

Reviewed integration baseline: `02ef38df8185c5f411dfc57f074ef5a7bea29384`
(2026-10-25). The issue, E17 gate, current AppSettings, Themes and parser source
were inspected. No app, UserDefaults domain or migration was launched.

## What is settled now

The following are settled **dispositions**, not writes to a MostlyText
preference:

| Legacy declarations | Settled disposition |
| --- | --- |
| `firstVersionInstalled`, `latestVersionInstalled` | Legacy provenance only. They never establish MostlyText first-run or migration completion. |
| `extensionTables`, `extensionFencedCode`, `extensionStrikethough`, `htmlTaskList` | Equivalent unconditional parser capabilities. `true` may be reported as already available; `false` has no disable setting and is reported as unsupported. |
| `extensionAutolink`, `extensionFootnotes` | Unsupported: CommonMark angle-bracket autolinks are not GFM extended autolinks, and footnotes are not supported. |
| `extensionIntraEmphasis`, `extensionUnderline`, `extensionSuperscript`, `extensionHighlight`, `extensionQuote`, `extensionSmartyPants`, `markdownManualRender` | Unsupported parser/render semantics; no proxy setting. |
| `supressesUntitledDocumentOnLaunch`, `createFileForLinkTarget`, `editorSyncScrolling`, `editorHorizontalInset`, `editorVerticalInset`, `editorLineSpacing`, `editorWidthLimited`, `editorMaximumWidth`, `editorOnRight`, `editorShowWordCount`, `editorWordCountType`, `editorScrollsPastEnd`, `editorEnsuresNewlineAtEndOfFile`, `editorUnorderedListMarkerType`, `previewZoomRelativeToBaseFontSize` | Unsupported until a final exact-equivalent setting exists. In particular, word-count visibility is not `showsStatusBar`, and no imported value may silently change saved bytes or layout. |
| `htmlTemplateName`, `htmlStyleName`, `htmlDetectFrontMatter`, `htmlHardWrap`, `htmlSyntaxHighlighting`, `htmlHighlightingThemeName`, `htmlLineNumbers`, `htmlCodeBlockAccessory`, `htmlDefaultDirectoryUrl`, `htmlRendersTOC` | No current exact legacy preference import. Never execute a template/CSS/script, treat an export setting as an editor setting, use a stored URL as a grant, or rewrite a document to obtain a TOC. |
| `editorBaseFontName`, `editorBaseFontSize`, `editorBaseFont`, `editorUnorderedListMarker` | Calculated from stored state only; never independently imported. |
| `filesToOpen`, `pipedContentFileToOpen` | Transient IPC; never replayed. |

The five former inert `MarkdownParseOptions` fields are resolved by E22's
current source, not by storing another preference: `tables`, `taskLists`, and
`strikethrough` are always parsed; GFM extended `autolinks` and `footnotes` are
not supported. `blockDirectives` is the sole current real switch and remains
off by default. No legacy extension key maps to it.

## Destinations that exist but are not frozen mappings

`EditorSettings` currently persists `font`, `autoIncrementOrderedLists`,
`convertsTabsToSpaces`, `continuesMarkdownPrefixes`,
`completesMatchingCharacters`, and `smartHome`. Their corresponding legacy
keys (`editorBaseFontInfo`, `editorAutoIncrementNumberedLists`,
`editorConvertTabs`, `editorInsertPrefixInBlock`,
`editorCompleteMatchingCharacters`, `editorSmartHome`) are **candidate
equivalents only**. Before any import writes them, freeze the final settings
schema and prove the conversion behavior below. Existing defaults are not proof
that a legacy default was absent.

`editorStyleName` is an E23 theme-policy dependency, not an existing
`ThemeController` selection mapping: only an approved, exact alias in the final
catalog can be offered. No nearest-name match, legacy style execution or custom
CSS import is permitted. `htmlHighlightingThemeName` is a legacy export
stylesheet, not a theme ID. `updateIncludesPreReleases`, `htmlMathJax`,
`htmlMathJaxInlineDollar`, `htmlGraphviz`, `htmlMermaid`, and
`htmlRendersTOC` remain owner-policy dispositions; they cannot manufacture an
update channel, renderer switch or export setting from a legacy Boolean.

## Destination defaults and precedence

The current product has five whole-JSON AppSettings domains (`general`, `editor`,
`markdown`, `previewExport`, `formats`) plus separate theme selection storage.
`EditorSettings` defaults include SF Mono 13, width 4, all assist booleans true,
and `showsStatusBar` true; `MarkdownSettings.parsesBlockDirectives` defaults
false. Those values apply only to an absent field/domain, not to a valid
persisted value that happens to equal or differ from the default.

1. Read the destination persistent domain, not a merged
   `dictionaryRepresentation`. Run compatible decoding before constructing a
   mutable model or seeding defaults.
2. A valid persisted MostlyText field always wins, including `false` and a
   value equal to the documented default. An absent field may receive a
   consented, exact legacy conversion. A user may explicitly select replacement
   per conflicting field.
3. A missing domain may be seeded. A known older domain is additive-migrated
   without resetting unrelated values. Malformed or future data blocks automatic
   replacement and is retained/reported verbatim.
4. The plan records source hash, destination raw hashes/schema generations,
   proposed values, warnings and dispositions. Recheck the destination digest
   immediately before commit; any mismatch replans rather than applying stale
   choices.

## Required pure conversion and admission rules

- Accept only bounded property-list primitives: at most 1 MiB snapshot, 2,048
  keys, 4 KiB ordinary strings, finite validated numbers, and a real CFBoolean
  rather than numeric/string coercion.
- Font conversion validates the legacy name/size, resolves an installed font at
  the AppKit boundary, and preserves the current font with a warning if it is
  unavailable. It never downloads a font.
- The five Boolean candidates retain literal Boolean meaning. Prefix continuation
  also needs list/quote behavior fixtures; tab conversion never invents a width.
- Invalid numeric/enum values, unknown keys, malformed dictionaries, URLs,
  executable CSS/templates/scripts and unapproved theme aliases are local
  report entries, never destination writes or security grants.

## Idempotence, interruption and recovery contract

E17 owns bootstrap, consent and a single serialized settings-write coordinator;
E23 owns safe theme insertion. Plan before applying. Journal mapping version,
source hash, per-domain before/desired digests and stable theme IDs, never raw
preference values. Stage, write one destination at a time, read back, then mark
complete only after every selected operation succeeds.

On restart, desired bytes mean already completed; recorded-before bytes allow
one planned retry; a third value is a conflict that is retained and reported.
Decline is an opt-out state, not completion. Rollback may restore only an
unchanged transaction-owned destination, never a later user edit. Repeating an
identical theme import must be a byte-identical no-op (or an explicit user
selection), not a new UUID/file. The original MacDown domain remains read-only.

## Required migration test contract

All automated fixtures use unique isolated suites/synthetic property lists;
they never open `com.uranusjr.macdown` or the user's standard defaults.

| Test group | Required assertions |
| --- | --- |
| Source/map coverage | Pinned header/implementation digests; all 58 declarations exactly once; no invented spelling/alias; every known key classified; calculated/transient keys cannot become writes. |
| Parser disposition | `blockDirectives` default false and wiring; tables/task lists/strikethrough parse unconditionally; extended autolinks/footnotes remain unsupported; no legacy extension flag creates an inert switch. |
| Compatible destination decode | Schema-less pre-E22 editor JSON retains nondefault font, width and disabled assists; missing `showsStatusBar` defaults only that field to true; present false remains false; missing mandatory field, wrong type, explicit null, NaN/infinite/out-of-range value, corrupt bytes and unknown future schema preserve raw data and report failure. |
| Pure legacy plan | Every Boolean candidate; installed/missing/invalid font; Unicode names; invalid enums; unknown keys; over-limit input; malicious URL/template/CSS; no mutation from plan construction; exact warning/disposition output. |
| Precedence and consent | Absent versus explicit false/default-valued destination; valid existing destination wins; per-field acceptance/rejection; whole-domain serialization preserves unselected fields; changed digest produces conflict/replan. |
| Apply and recovery | Failure before/after each write, read-back and completion marker; restart at before/desired/third value; repeated plan/apply/relaunch; no duplicated theme ID/file; rollback cannot overwrite a later normal edit; unreadable/future destination values are retained. |
| E17 isolated rehearsal | Original-MacDown consent import separately from development/beta identity migration; nondefault settings, theme selection/custom theme, session/recovery/bookmarks/snippets and disposable caches; interruption and two relaunches; inspect original and destination snapshots for no loss/duplication. This is real-app evidence, not satisfied by the pure tests. |

Declaration-map validation ran: the checker and its 11 unit tests. The
migration tests above remain future work; no migration was executed or
activated, and no live preferences were touched.

## Stop conditions

Do not begin shipping migration code until E22's parser result and E23's final
theme/settings surface are frozen, the protected destination writer accepts the
contract above, and E17 has adopted the same coordinator and journal. Stop and
escalate on an unclassified legacy key, a purported equivalent without semantic
fixtures, an overwrite of unreadable/future data, a source-domain mutation, or
non-idempotent replay.
