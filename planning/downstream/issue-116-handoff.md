# Issue #116 — One math grammar, useful errors and accessible equations

## Owner summary

Math should mean the same thing in Preview and Export, malformed equations should explain the problem, and a screen-reader user should encounter the equation rather than an anonymous image. Fix the actual tokenizer/renderer boundary; do not keep adding invisible-character substitutions to authored prose. Keep the native preview and existing offline typesetter.

Baseline: `83a79a4572e23a781b2cf370dd2b407fe7409d09`, reviewed 2026-09-24. This is deferred architecture outside E22. Preserve E22's editor/selection ownership and consume its final source-coordinate contract. #113 consumes these results; #118 verifies exported artifacts; #88/#115 supply final GUI/evidence closure.

## Repository and upstream reconciliation

Read MathSpanScanner, MathImageRenderer and native Preview BlockView. Also read the exact pinned Textual 0.5.0 PatternTokenizer and SwiftUIMath 0.1.0 Math.swift/Parser.swift. #116 had no comments.

The repository scanner intentionally diverges from Textual for escaped dollars. Textual's actual tokenizer has no escape-pair handling. The app's renderer uses zero typographic bounds as its only validity test and performs rendering synchronously on MainActor. However, SwiftUIMath's internal `Math.ParserError` already distinguishes mismatched braces, invalid commands, missing delimiters/environments and an internal-error code. Exposing that result is narrower than implementing a second LaTeX validator.

## Chosen ownership and dependency changes

Keep MacDownKit's Math module as the public document-math interface. Extract only delimiter tokenization and its small Sendable range/style values into a standalone local `MathSyntax` package depending on Foundation alone. Both the Math adapter and a narrowly patched Textual dependency consume that implementation. A standalone package avoids a Textual -> MacDownKit -> Textual dependency cycle. Do not make upstream view code depend on Workspace, FileCore or the app.

Vendor the currently pinned Textual and SwiftUIMath source as local packages, preserving licenses/notices and recording exact upstream tag/commit/tree hashes plus a patch manifest. Keep SwiftUIMath resolved to ONE identity for Textual and MathRendering. Do not patch `.build/checkouts`, introduce a floating fork branch, or upgrade unrelated package versions. Authorize changes only to delimiter integration, equation attachment metadata/accessibility and a structured parser-result adapter. Compare the vendor tree against its recorded upstream before accepting it; unrelated diffs stop this slice.

Expose an app-facing `MathAnalysis` containing admitted spans and diagnostics. An equation identity includes document identity, original source UTF-16 range, source generation, style and expression digest. Cache expensive expression/layout results by expression/style/font/size/palette/engine version; do not use source offsets as the sole content cache key. Navigation identity and reusable render identity are different concepts.

## Delimiter policy v1

MathSyntax performs a bounded left-to-right scan; no regex is recompiled per position and no suffix is rescanned quadratically. Both consumers use it, not copies of its patterns. CommonMark structural admission excludes front matter, fenced/indented code, inline code, link destinations and raw HTML attributes/blocks. Retain existing literal-code tests. Admit prose/math content only in contexts supported by both consumers.

An unescaped `$$` pair denotes nonempty display math, with display recognition taking precedence over inline. Display content may cross lines, but not structural exclusion boundaries. An inline opening `$` must be followed by a non-whitespace character. Its closing unescaped `$` must follow a non-whitespace character and must not be immediately followed by a digit; inline math never crosses a line break. This deliberately protects common prices such as `$5 and $10`; `$5$` remains explicit numeric math. Unpaired delimiters stay literal. `$x$2` stays literal under this documented flanking rule, not a secretly guessed exception.

Escape handling uses the parity of the complete immediately preceding backslash run, including at block boundaries. It must distinguish `\$` from `\\$`; skipping every backslash-dollar pair regardless of earlier backslashes is not sufficient. Export and Textual consume identical admitted tokens. Textual's `.math` extension delegates to the shared scanner and respects code precedence, rather than running an old second tokenizer after preprocessing.

Store both full delimiter range and expression-body range. Source coordinates remain original-source UTF-16. Front-matter removal, block slicing and prepended reference definitions use an explicit offset map; the rendered block's offsets are not original file offsets. Never add an equation after parsing synthetic reference definitions that were not authored math.

## Structured validation and rendering

Add a narrow public immutable SwiftUIMath analysis result backed by its own Parser. Distinguish invalidSyntax(code, optional expression-relative error offset), unsupportedConstruct, valid and internalFailure. Map internalError/typesetting/image-encoding failures to renderer failure, not 'your equation is invalid'. If the parser only reports an end cursor, label the range approximate; do not invent a precise offending token.

MathRendering converts these results to stable domain diagnostic codes. Validate once per expression/configuration identity and reuse that result for native rendering and PNG export. Avoid parsing on every SwiftUI body evaluation. Empty or zero-area valid constructs must not automatically become syntax errors; a successful parse followed by invalid/nonfinite layout bounds is a separate layout result. Bound source length, recursion/depth where exposed, output dimensions and raster pixel count before ImageRenderer allocation. Preserve or tighten existing E19 budgets; record any new ceiling in one policy, not caller literals.

Rendering stays on the executor required by SwiftUI/AppKit. Pure scanning and value processing run off MainActor. Cache confinement must be explicit because upstream DisplayProvider is shared; do not declare a mutable parser/display tree Sendable merely to silence strict-concurrency errors. Use confined immutable results or a documented serialization boundary. Cancellation occurs between bounded units; there is no claim that one synchronous equation render is preemptible. A pathological single equation exceeding the verified bound is a release blocker requiring a narrow typesetter fix, not a larger timeout.

## Accessibility and source navigation

Patch equation attachment/presentation metadata so native Preview exposes one accessible equation element per equation, with role/description identifying inline or display math and a meaningful label containing readable LaTeX source. Preserve surrounding paragraph reading order. Provide a localized 'Reveal equation in source' action resolving the current identity through the existing source-navigation path. A stale generation cannot select a different range after editing.

Do not solve accessibility by hiding the whole paragraph and replacing it with one label, duplicating every equation announcement, or putting a disconnected invisible list at the end of the document. Where the native inline attachment cannot expose an independent element, the authorized Textual patch must provide an appropriate attributed-text/accessibility representation while retaining inline layout. Actual VoiceOver reading order and discoverability are the acceptance gate; presence of an accessibility modifier alone is not.

Exported equation images retain escaped `alt` text with the expression, style and bounded diagnostics where applicable. Preserve logical dimensions separately from pixel scale; #62's sizing fix must stay covered. This does not claim natural-language mathematical speech, MathML-level semantic exploration or fully tagged accessible PDFs. Those must not be advertised as implemented from a source label alone.

## Diagnostics and failure lifecycle

Publish diagnostics per document generation with equation identity/range. Invalid equations keep readable source in place and do not break surrounding content. Internal failures have a distinct retryable presentation. Limit visible diagnostics, deduplicate identical errors and use a summary count; do not send a screen-reader announcement on every keystroke. When a valid new generation publishes, replace the old diagnostic set atomically so fixed errors disappear. On cancellation or stale completion, publish neither old errors nor old rendered glyphs.

Selection, copy, undo and source-on-disk remain unchanged by rendering. No remote LaTeX service, arbitrary TeX execution, shell command, network font or document rewriting is introduced.

## Six acceptance areas and evidence

1. Diagnostics: invalid command, unmatched brace, missing environment, empty valid content and injected internal render failure produce discriminating structured outcomes. Correcting each removes the old diagnostic.
2. Accessibility: real VoiceOver traversal of prose with two inline equations and a display equation; discover/reveal each source range; no anonymous image or duplicated paragraph.
3. Escaped-dollar parity: `Price: \$5 and $x=1$ today.`, odd/even backslash runs, adjacent equations, `$5 and $10`, `$5$`, multiline display, code spans/fences and CRLF. Assert identical recognized spans in the actual Textual adapter and Export, not just two mocks of MathSyntax.
4. Visual regression: real native Preview and genuine exported HTML/PDF, light/dark and print, rechecking #62's literal code and logical-size fixes.
5. Grammar ownership: both integrations call MathSyntax; the old Textual regex path is unavailable in the app's math mode. Document grammar examples and literal fallback.
6. Navigation: original UTF-16 equation ranges survive CJK, emoji, combining marks, front matter and reference-definition prefixing; stale ranges refuse navigation. Display equations and supported inline elements reach the intended source.

Keep the existing 100-equation performance corpus and add deeply nested and maximum-size expressions, repeated invalid equations, theme changes and rapid revision supersession. Record cold/warm parse/layout/raster durations and peak memory in Release. No old benchmark threshold is weakened to pass a vendoring change.

## Single implementation sequence

A. Vendor the exact pinned dependencies and introduce the Foundation-only MathSyntax package with pure grammar/golden tests. Verify package identity/dependency graph and unchanged licenses. Stop if a cycle or unrelated upgrade is needed.

B. Delegate Textual's math tokenization to MathSyntax and expose SwiftUIMath parser outcomes. Test the real dependency adapters before changing presentation.

C. Add diagnostic/cache identity and equation accessibility/source actions; update the app preprocessor to remove obsolete workaround paths only when the real parity tests pass. Allowed areas are Math/MathRendering, Preview's math integration, app MathPreviewPreprocessor/MathExportRegistry, dependency adapters and corresponding tests/catalogs. No E22 edit transactions or save paths.

D. Execute all six acceptance areas, Release/full package/app validation and real VoiceOver/PDF checks through #88. Update the E19 residual ledger and #115. A compiler pass cannot stand in for attachment accessibility or visual verification.

## Architecture review

Self-review addressed a dependency cycle from importing app Math into Textual; duplicate SwiftUIMath package identities; false syntax errors from zero size; even/odd backslash handling; code precedence; original/rendered offset confusion; stale navigation; cache reuse across palettes; and claiming synchronous layout can be forcibly cancelled. Narrow upstream adaptation is an explicit implementation choice, not a request for the implementer to invent a new renderer.

This hand-off contains no measured PASS and no claim that a newly patched accessibility path has already been tested. All six residuals require implementation evidence before #116 can close.

## Inspected primary source

- https://github.com/gonzalezreal/textual/blob/0.5.0/Sources/Textual/Internal/MarkdownParser/PatternTokenizer.swift
- https://github.com/gonzalezreal/swiftui-math/blob/0.1.0/Sources/SwiftUIMath/Math.swift
- https://github.com/gonzalezreal/swiftui-math/blob/0.1.0/Sources/SwiftUIMath/Internal/Syntax/Parser.swift
