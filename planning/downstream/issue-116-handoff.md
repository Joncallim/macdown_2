# Issue #116 — One source-aware math path

## Owner summary

Preview and Export must agree on equations, preserve ordinary currency and literal code, explain invalid math, and expose each equation to accessibility and source navigation. Keep the native preview and existing offline typesetter. The change is a narrow parser/attachment adaptation, not a replacement Markdown view.

Reviewed baseline: `b95fe439672dbcad4e5c9d04f7f353ffc85ff26b`, 2026-09-26. Original architecture is preserved in #125 / commit `b2c6d19`. Read [README](README.md) and [readiness review](READINESS_REVIEW.md). Implementation follows completed E22; this document does not change its active work. Issue #116's six acceptance areas remain mandatory.

## Baseline and corrected premise

MathSpanScanner, MathImageRenderer, MathPreviewPreprocessor and Preview's BlockView are unchanged from the originally inspected source. E22 now supplies `EditorTextSystem.selectionSet`; downstream navigation must use its deliberate single-range/reveal path, not write NSTextView ranges directly and resurrect cached secondary carets.

Pinned Textual 0.5.0 `AttributedStringMarkdownParser.PatternProcessor.expand` tokenizes EACH attributed run AFTER Markdown parsing. Backslash escapes and Markdown formatting have already been interpreted, and soft-line breaks may separate runs. Therefore the original proposal to call MathSyntax only from PatternTokenizer is insufficient: it cannot recover an escaped dollar or equation syntax already changed by Markdown. This revision explicitly replaces that proposal.

The existing preprocessor collapses equation newlines and substitutes an invalid-math marker. Newline collapse is not generally harmless to TeX, especially a percent-comment whose meaning ends at a newline. Preserve the original equation body. SwiftUIMath 0.1.0 already has internal structured ParserError codes; expose those rather than write a competing LaTeX validator.

## Ownership and dependencies

A small standalone Foundation-only `MathSyntax` package owns raw delimiter tokenization, expression/full-span UTF-16 ranges and immutable transport values. MacDownKit Math and a narrow pinned Textual adaptation consume that package. Textual must not depend on MacDownKit, Workspace or the app. Keep one SwiftUIMath package identity for Textual and MathRendering.

Vendor the exact currently pinned Textual and SwiftUIMath sources only for the required adaptation, retaining upstream commit/tree identifiers, licenses and a patch manifest. Do not patch .build/checkouts, use a floating fork or upgrade unrelated packages. Before coding, verify actual dependency identity and all transitive products resolve once. A different parser/dependency architecture requires a focused revision, not silent widening.

Math owns document-structural admission and MathAnalysis. The patched Textual parser accepts pre-admitted local-source spans and converts them into its existing equation attachment representation. MathRendering owns structured analysis/layout/image production. The app binds equation navigation to document lifetime. Export consumes the same admitted MathAnalysis, with its existing first-party image renderer and destination policy.

## Source admission and grammar v1

Run on an immutable ORIGINAL source snapshot before any Markdown rendering transform. Exclude front matter, top-level and nested fenced/indented code, inline code, link destinations and raw HTML attributes/blocks using parsed source ranges plus the existing tested lexical exclusions. Do not adopt E22's hot-key approximate fence classifier as the authoritative document parser. Delimiter scans cannot cross excluded regions. Generated TOC/reference-definition text is not authored math.

MathSyntax is a single forward scan with bounded delimiter lookahead and no repeated suffix regex search. Track the parity of complete consecutive backslash runs; odd escapes a dollar, even does not. Display `$$` takes precedence over inline `$`; require a nonempty body and preserve internal newlines. Inline opening must be followed by a non-whitespace character; closing must follow non-whitespace and not immediately precede a digit. Inline never crosses a line boundary. Unpaired or partially typed spans stay literal without a diagnostic.

Recovery rule is essential: when an inline candidate meets an unescaped dollar that is not a valid closer, abandon that candidate as literal and reconsider this new dollar as a potential opener. Do not keep searching farther forward and swallow a later valid equation. Thus `$5 and $10; then $x$` preserves prices and admits only `$x$`. `$5$` is explicit numeric math; `$x$2` is literal under this documented policy. Fixtures lock ambiguous cases rather than adding ad hoc exceptions. Display candidates cannot consume another structural block merely because a dot-all regex can find a distant closer.

Return full delimiter range, body range, original expression bytes/style and a source identity. Preserve original-source UTF-16 coordinates. UTF-8 bytes, NSString offsets and grapheme columns are distinct. A renderer input is not permission to recompute source ranges by searching repeated expression text.

## Pre-parse transport through Textual

Chosen mechanism: a narrowly scoped opaque-marker transport around the actual Textual Markdown parser, followed by typed attachment construction. It changes only the transient render input; it NEVER changes authored text, FileDocument state, disk bytes, undo or copied source.

1. For an admitted block, assign each equation an opaque ASCII-alphanumeric marker from a per-render namespace proven absent from the complete parser input, including prepended reference definitions. Markers are generated by the adapter; authored URLs/HTML cannot register one. Check namespace absence once, not a full source rescan per span.
2. Replace only admitted full equation spans, from original offsets, with their markers. Maintain an explicit segment map between original source, rewritten block and prepended definitions. The marker shields LaTeX underscores, stars, backslashes and line breaks from Markdown interpretation.
3. Parse that transient input through the existing Textual Markdown path with its old `.math` PatternProcessor DISABLED. Do not run a second dollar tokenizer on the attributed output. Other admitted syntax extensions retain their own behavior.
4. Find generated markers across attributed runs within the parsed text container, not only within each run. Replace each registered marker exactly once with the existing typed inline/display equation attachment, retaining surrounding link/emphasis/paragraph attributes and equation identity. All markers must resolve; a missing/duplicated/misplaced marker is an adapter failure with original-source fallback, never leaked opaque text or guessed navigation.
5. Render the unchanged equation body via SwiftUIMath. The adapter may copy stable style values but does not carry mutable parser/DOM objects across executors. Display attachment placement is explicit; preserving inline font metrics is tested against actual surrounding text.

Do not use a magic authored URL, user-recognizable replacement syntax or an invisible-character substitution as trusted input. The random namespace is transport-only and absent from persisted IDs/cache keys/exports. Export does not consume these markers: it uses original admitted source ranges and its existing derived-content pipeline.

### MATH-ADAPTER probe — first executable unit

Build one actual pinned Textual parser/attachment integration test before broad implementation. Inputs: escaped dollar followed by real math, equation with Markdown punctuation, multiline display with a percent-comment, equation inside emphasis/link label, literal code, repeated identical equations and an intentionally missing marker. Output: native attachments plus exact original ranges, or readable fallback with no marker leakage. Verify normal paragraph reading order/layout and one SwiftUIMath identity. Failure stops only this adapter integration for a focused revision; pure grammar/diagnostic work may continue. This probe has not run in this architecture session.

## Validation, layout and bounded work

Expose immutable SwiftUIMath parser outcomes: valid, invalidSyntax(code, optional body-relative location), unsupportedConstruct and internalFailure. Map parser internalError, nonfinite/oversized layout and PNG encoding failure to renderer errors rather than blame the user's syntax. If only an end cursor is known, mark its location approximate. Zero-area output is not independently proof of invalid syntax.

Analyze once per expression/style/font/size/engine version. Rendering/cache identity additionally includes destination palette and raster scale; navigation identity includes document ID, recovery epoch/lifetime, source generation and original range. Do not let a cached image's old location become its new navigation target. Reuse immutable analysis, not mutable upstream parser/display state. Audit shared DisplayProvider confinement before parallel use.

Scanning and value processing run off MainActor on explicitly selected bounded workers. Swift 6.2 `async`, `nonisolated` or Task{} alone does not prove that a function leaves the caller's actor; preserve current compiler settings and test the actual boundary. SwiftUI/AppKit raster work stays where the API requires it. Retain existing E19 size/count/100-equation budgets; bound nesting, finite logical dimensions and checked raster-pixel multiplication before allocation. Cache by byte cost with bounded negative results. Cancellation stops queued work and rejects stale results; one synchronous render is not promised to be preemptible.

The previous 256-span preprocessing cap cannot leave the remainder to an unbounded hidden Textual math pass. Admit at most the trusted policy's spans; all excess spans stay source. A worker/queue slot is released on actual completion, not merely on waiter cancellation. Pathological single-expression behavior must meet the named probe/calibration or receive a narrow renderer fix before release.

## Accessibility, navigation and diagnostics

Expose each native inline/display equation as one meaningful accessible element or attributed equivalent with role/label and readable original LaTeX. Preserve surrounding paragraph reading order. Add a localized Reveal equation in source action routed through the existing controller's single-selection/reveal operation. Validate document lifetime/generation at execution; stale ranges refuse navigation. Never clear or alter selections during rendering itself.

Do not hide the whole paragraph behind a replacement accessibility label or add a disconnected invisible equation list. Native attachment support is proved through actual accessibility-tree and VoiceOver traversal, not the presence of a modifier. Export images carry properly escaped alt text and logical dimensions independent of pixel scale. This does not claim MathML exploration, natural-language mathematical speech or tagged-PDF accessibility.

Invalid admitted equations retain readable source plus bounded source-anchored diagnostics; unfinished/literal currency does not emit errors. Publish the new diagnostic set atomically per accepted generation, deduplicate repeated messages and avoid keystroke-by-keystroke announcements. Corrected source clears prior diagnostics. Cancellation cannot publish old errors or old glyphs. All new messages use the proper resource catalog/bundle.

## Implementation units and acceptance evidence

A. MathSyntax grammar/exclusions and pure tests; narrow dependency vendoring and dependency-identity check. No editor/save changes.
B. MATH-ADAPTER real parser/attachment probe; parser-error adapter. Stop on unresolved markers, source-map disagreement, dependency cycle or mandatory accessibility capability unavailable through the proposed patch.
C. Replace preprocessor workaround paths with source-aware transport; diagnostics/cache/accessibility/navigation. Preserve native preview and existing Export renderer. Remove old paths only when genuine adapter parity tests pass.
D. Full regression, Release performance and live native/HTML/PDF/VoiceOver verification, then E19/#115 evidence reconciliation.

Tests must cover all six issue areas: structured invalid/internal outcomes and recovery; equation accessibility; escaped-dollar parity; live post-#62 code/sizing/ordinary-math checks; currency grammar; own-span navigation. Include odd/even escapes, `$5 and $10; then $x$`, multiline comments, nested fences/quotes/lists, CRLF, CJK/emoji/combining marks, link labels/destinations, theme changes, rapid revisions, duplicate expressions and maximum-size/100-equation corpora. Test actual Textual and Export adapters against the same expected source tokens, not two mocks calling one scanner.

Run repository serial formatting/strict lint, targeted Math/MathRendering/Preview and app integration suites, full package/app suites and Release build. Through #88 verify light/dark/high-contrast native display, genuine exported HTML/PDF, source selection and VoiceOver reading order. Build-only is not a pass. No current E22 file mutation is authorized by this document.

## Review disposition

The second review corrected the lossy post-parse seam, newline/TeX-comment corruption, dollar recovery crossing later math, marker/source identity leakage, cap bypass through a second tokenizer, stale primary/secondary selection handling and unsafe cache/executor assumptions. Architecture choices are fixed; the named native adapter probe and final execution evidence remain outstanding. #116 closes only when all six acceptance areas actually pass.

Inspected primary code: Textual 0.5.0 `Sources/Textual/Internal/MarkdownParser/PatternProcessor.swift`; SwiftUIMath 0.1.0 `Sources/SwiftUIMath/Math.swift` and `Internal/Syntax/Parser.swift`; current app `MathPreviewPreprocessor.swift` and E22 `EditorTextSystem+Selection.swift`.
