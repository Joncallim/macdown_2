# Issue #53 — Legacy preference import without false parser controls

## Owner summary

Offer a local, explicit import of useful original-MacDown preferences without changing its installation, reviving unsupported parser switches or overwriting settings the user has already chosen in the new editor. Every old key receives a disposition and the user sees what cannot transfer. Repeating or recovering an import must not reapply old choices over newer ones.

Baseline: `83a79a4572e23a781b2cf370dd2b407fe7409d09`, reviewed 2026-09-24. This hand-off covers only E17's import half. E22 (#112) exclusively owns eliminating/recasting the five inert MarkdownParseOptions fields; do not edit its implementation, tests or future slices. #53 closes only when both owners provide evidence. Implement the import after E22/E23 freeze the actual settings/theme schema, but before the final E16 string freeze and production authorization.

## Source reconciliation

Read LegacyPreferencesDetector, UserDefaultsAppSettingsStore, EditorSettings, GeneralSettings, MarkdownSettings and PreviewExportSettings at the baseline. Read original MacDown's `MacDown/Code/Preferences/MPPreferences.h` and `.m` at exact upstream ref `3e2a2bf101c215c143bf00d9f857965f0ee82487`. The legacy domain is `com.uranusjr.macdown`; the detector intentionally checks only its persisted domain. Do not initialize the old MPPreferences class: its initializer writes defaults, version keys and cleans autosave entries.

Current settings are whole JSON values under appSettings.general/editor/markdown/previewExport/formats, not independent UserDefaults entries per field. Treating a decoded default as 'unset' would overwrite a deliberate choice. The current launch enum restorePreviousSession/startWithNewDocument is not the same thing as the old suppression-of-untitled Boolean.

## Interfaces and ownership

AppSettings owns pure `LegacyPreferenceSnapshot`, `LegacyImportPlan`, `LegacyKeyDisposition` and conversion/validation functions. E17's application migration coordinator owns consent, serialized persistence, rollback/recovery journal and publication into AppSettingsModel/ThemeController. E23 owns theme-file validation/catalog insertion. No importer executes old CSS/templates, unarchives arbitrary objects, reads old IPC requests or grants directory access.

A plan is immutable and includes source-domain hash, destination-domain raw hashes, per-field desired values, source provenance, warnings and rejected keys. Every input key is classified as mapped, equivalent-unconditional, unsupported, obsolete, transient, invalid or unknown. Mapped does not mean applied: existing destination ownership may cause a mapped value to be retained as a suggestion only.

Initial admission: property-list primitives only, 1 MiB total snapshot, 2,048 keys, 4 KiB ordinary strings, finite bounded numbers and strict type checks. CFBoolean is distinguished from arbitrary NSNumber; do not coerce the string 'false', arrays or numbers other than the explicitly allowed legacy Boolean representation. Unknown keys remain in the local audit report, never in the new settings domain.

## Complete declared-key disposition

This is the baseline disposition of every declared stored preference from the inspected original header. At post-E22/E23 reconciliation, fill the final destination symbol for any newly available exact semantic equivalent; do not infer equivalence from a similar key name. Newly discovered historical/runtime keys must also appear in the report. A coverage test compares the checked-in legacy key inventory with the disposition manifest and refuses unclassified entries.

| Original stored key | Conversion / disposition |
| --- | --- |
| firstVersionInstalled | Obsolete original-app bookkeeping; preserve only as import provenance, never as the new app's first-run/version state. |
| latestVersionInstalled | Same; cannot mark the new installation initialized or migrated. |
| updateIncludesPreReleases | Record as an update-channel suggestion. E17 defaults to stable; enable a prerelease channel only through a supported, explicitly confirmed new-product choice. Never import old Sparkle security/feed keys. |
| supressesUntitledDocumentOnLaunch | No exact baseline equivalent. Do not map to session restoration. If the final launch model contains this precise choice, map explicitly; otherwise report unsupported with source value preserved. Retain the original misspelling in the key inventory. |
| createFileForLinkTarget | Unsupported unless the final app has the identical explicit action policy. Never enable automatic file creation just from import. |
| extensionIntraEmphasis | Original parser-specific behavior, not a general 'Markdown enabled' switch. Record unsupported/different grammar. |
| extensionTables | E22 supplies the final unconditional-capability disposition or real toggle; do not import a no-op Boolean. |
| extensionFencedCode | Core supported grammar, no equivalent toggle; report equivalent-unconditional for true and unsupported disable request for false. |
| extensionAutolink | Consume E22's actual autolink capability; no inert field import. |
| extensionStrikethough | Preserve the misspelled original key; consume E22's actual strikethrough capability, not an invented corrected legacy key. |
| extensionUnderline | Unsupported grammar difference; do not map to editor underline formatting. |
| extensionSuperscript | Unsupported grammar difference unless the final parser explicitly implements it. |
| extensionHighlight | Unsupported grammar difference; not the same as syntax highlighting. |
| extensionFootnotes | Consume E22's final footnote capability; no inert field import. |
| extensionQuote | Original parser extension, not ordinary block quotes; unsupported unless explicitly equivalent. |
| extensionSmartyPants | Unsupported parser typography; do not silently mutate punctuation or enable system smart substitutions. |
| markdownManualRender | Unsupported manual-render policy at baseline. Do not map to hiding Preview; report the distinction. |
| editorBaseFontInfo | Validate dictionary keys name/size. Resolve the old PostScript font name through NSFont on MainActor to the actual new FontDescriptor family/size; preserve the installed font when valid, otherwise retain current font and report unavailable. Never download a font. |
| editorAutoIncrementNumberedLists | Map Boolean to editor.autoIncrementOrderedLists. |
| editorConvertTabs | Map Boolean to editor.convertsTabsToSpaces; do not infer indentation width, which this key does not encode. |
| editorInsertPrefixInBlock | Map Boolean to editor.continuesMarkdownPrefixes after its list/quote behavior fixture passes. |
| editorCompleteMatchingCharacters | Map Boolean to editor.completesMatchingCharacters. |
| editorSyncScrolling | Map only to the final shared scroll-sync preference if exposed. If not user-configurable, classify the current unconditional policy, not defaultPreviewLayout. |
| editorSmartHome | Map Boolean to editor.smartHome. |
| editorStyleName | Resolve only a curated, versioned exact legacy-theme alias to an E23 catalog ID. Unknown/custom named styles need explicit safe conversion/import; never select an unrelated theme by nearest name or copy executable style text. |
| editorHorizontalInset | Map finite value only if final editor offers the same unit/meaning; otherwise unsupported layout customization. Do not confuse margin with document/page width. |
| editorVerticalInset | Same exact-unit rule; no silent mapping to line spacing. |
| editorLineSpacing | Map only an actual line-spacing setting after verifying points versus multiplier. Do not insert newlines or change font size. |
| editorWidthLimited | Unsupported at baseline; map together with editorMaximumWidth only to an exact completed width-policy equivalent. |
| editorMaximumWidth | Validate finite positive point width and companion enable flag; an unused saved number alone cannot enable a new width restriction. |
| editorOnRight | Unsupported pane-order preference unless final layout explicitly supports it; split mode is not equivalent. |
| editorShowWordCount | Map to the final E22 word-count visibility control if it exists. A fixed status display is an unconditional-policy disposition. |
| editorWordCountType | Map through an explicit old-enum/new-enum table only; otherwise unsupported counting mode. Never cast integer raw values between unrelated enums. |
| editorScrollsPastEnd | Map to a final exact scroll-past-end preference; otherwise report unsupported, not a fake stored switch. |
| editorEnsuresNewlineAtEndOfFile | Do not enable byte-changing save normalization from migration. Preserve as a suggestion only if a separately approved final setting exists; existing source-fidelity defaults remain unchanged. |
| editorUnorderedListMarkerType | Original 0 -> '*', 1 -> '+', 2 -> '-'. Map only to an actual preferred-new-list marker setting; unsupported otherwise. Invalid enum values are reported, not silently mapped to another marker. Existing document markers are never rewritten. |
| previewZoomRelativeToBaseFontSize | Unsupported scale-coupling policy unless final equivalent exists; do not alter editor font as a proxy. |
| htmlTemplateName | Original 'Default' maps to the current fixed first-party export template only as an equivalent-policy report. Other templates are unsupported executable markup; do not import them or mis-map to an export format. |
| htmlStyleName | No direct equivalent to embedded/linked style embedding. Report unsupported legacy CSS stylesheet; only a deliberate E23-compatible safe theme conversion may create a theme. |
| htmlDetectFrontMatter | Record the actual final parser's supported/unconditional front-matter behavior. Never map to blockDirectives. |
| htmlTaskList | Consume E22's task-list capability disposition; no inert toggle. |
| htmlHardWrap | Rendering semantics differ from editor line wrapping. Unsupported unless a real final hard-break parser/render option exists. |
| htmlMathJax | Record math-engine change and supported capability. Do not import a MathJax runtime, URL or enable flag as a hidden preference. |
| htmlMathJaxInlineDollar | Report #116's shared delimiter policy and any unsupported old disabling behavior; no second syntax switch. |
| htmlSyntaxHighlighting | HTML code highlighting policy, not editor syntax highlighting. Only map a real final export-highlighting control; otherwise classify current policy. |
| htmlHighlightingThemeName | Legacy HTML/highlight stylesheet, not an E23 editor-theme ID. Unsupported unless a curated semantic conversion exists. |
| htmlLineNumbers | Exported code-block line numbers, not E22's source gutter. Never map one to the other. |
| htmlGraphviz | Record local Graphviz capability; no import of old renderer scripts or flags that do nothing. |
| htmlMermaid | Same disposition for the local Mermaid engine. |
| htmlCodeBlockAccessory | Unsupported legacy code-block accessory enum unless an exact final equivalent exists. Do not cast into a new enum. |
| htmlDefaultDirectoryUrl | Never turn a stored URL into a resource capability. May seed a destination picker only after safe URL validation and an explicit user selection; otherwise retain as an unsupported convenience. No background enumeration/read grant. |
| htmlRendersTOC | Report the explicit [TOC] contribution policy from #117; do not automatically insert a marker or rewrite documents. |

Calculated header properties editorBaseFontName/editorBaseFontSize/editorBaseFont/editorUnorderedListMarker are not additional independent stored preferences. filesToOpen/pipedContentFileToOpen are transient interprocess requests, never replayed by migration. Legacy window/split-frame autosave keys, NSGlobalDomain settings and unknown Sparkle state are not bulk-imported. Enumerate any persisted framework/PAPreferences-prefixed aliases actually encountered and validate their relationship against the pinned implementation before accepting them; no suffix guessing.

## Destination precedence and consent

Read `persistentDomain(forName:)`, not dictionaryRepresentation, which merges registered/global/argument defaults. A missing destination JSON blob permits mapped values to seed a newly constructed typed domain. An existing valid blob protects every existing field by default, including values equal to today's defaults. Existing corrupt/unknown-version blobs are retained for recovery and block automatic replacement; do not treat a decode fallback as proof that no user settings exist.

Show an explicit import summary with applicable values, existing values retained, unsupported settings and invalid input. Default mode imports only genuinely absent destination domains/fields with reliable provenance. Replacing specific existing fields requires the user's explicit selection in this UI. Preserve every unselected field when writing a whole JSON domain. A global 'import completed' flag cannot justify clobbering later edits.

Use one serialized settings-write coordinator shared by migration and normal settings mutations. Validate the destination generation/raw hashes again at commit. If a user edits settings while the plan is open, re-plan and present changed conflicts; never apply a stale preview. Domain values already written by a prior completed migration are not automatically overwritten when the source MacDown preferences later change.

## Restart-safe application

Acquire an application-scoped migration admission token. Snapshot source/destination bytes read-only; create a restricted local journal with transaction ID, versioned mapping policy, per-domain before/desired digests and source provenance. Stage the complete typed destination values and validate them before any mutation. No network, telemetry, source-file access or arbitrary object decoding is part of this operation.

Apply through the same serialized persistence boundary, recording each committed domain and reading it back. Mark completion only after all intended writes and validated theme insertions are acknowledged. UserDefaults is not a multi-key transactional database; the journal and replay rules explicitly handle partial completion. On restart, a domain equal to desired is already applied; equal to captured before may be applied once; a third value is a conflict to preserve and show, never overwritten by blind replay. Do not assume synchronize provides filesystem-level atomicity.

A declined import records a separate opt-out/version state; opening Settings may still offer an explicit later import. If an import partially fails, keep original MacDown unchanged, retain destination changes already accepted and report exactly what needs retry. Rollback restores only values still owned by that transaction and unchanged since it wrote them. Never roll back over later user edits.

## Implementation order, tests and completion

1. After E22/E23, bind this semantic table to exact final destination fields, populate a checked-in machine-readable inventory/disposition manifest, and validate all keys. Include E22's five-field removal/capability evidence without editing E22.
2. Implement pure conversion/plan tests and structured invalid/unsupported reports. Exercise absent, false, default-valued, invalid-type, NaN, wrong-enum, missing-font, Unicode names, old theme aliases, malicious URLs and all declared keys.
3. Implement serialized consent/provenance/journal persistence; inject failure before/after every domain/theme write. Test repeated runs, source changes, partial recovery, destination changes while the summary is open, corrupt destination JSON, explicit overwrite selection and untouched legacy domain.
4. Integrate the existing first-run/Settings surface and all localized copy before #17's final freeze. Verify live settings apply through existing controllers and only the confirmed choices change. Do not create an E17-only unreviewed onboarding redesign.
5. Run affected AppSettings/Theme/migration tests, full package tests, strict format/lint, Release app build and a real isolated-account migration under #88. Record input/output manifests without exposing the user's private preference values in public logs.

Allowed files: AppSettings import value types/tests; E17 migration coordinator; existing first-run/Settings integration/catalogs; E23 theme-import API integration. No original-app files, E22 parser implementation or unrelated document state.

Stop on an unclassified meaningful final-equivalent key, inability to distinguish persisted settings from fallback defaults, overwriting a protected destination, unsafe theme/resource import or a non-idempotent failure path. #53 closes only after the importer and E22 parser half both have actual evidence in #115.

## Self-review

Review corrected legacy spelling mistakes, font PostScript-versus-family conversion, line-number and hard-wrap false equivalents, old launch-suppression versus restoration, whole-blob default-value clobbering, untrusted CSS/URLs, framework transient IPC replay, and multi-key UserDefaults crash consistency. Unsupported settings are an explicit user-visible disposition, not falsely reported as migrated.

Primary source: https://github.com/MacDownApp/macdown/blob/3e2a2bf101c215c143bf00d9f857965f0ee82487/MacDown/Code/Preferences/MPPreferences.h and adjacent MPPreferences.m. This is architecture evidence, not a migration of the owner's actual preferences.
