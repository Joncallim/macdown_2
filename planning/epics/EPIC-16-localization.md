> **Title:** [EPIC-16] Localization: String Catalogs + Transifex migration
> **Labels:** `epic`, `polish` · **Milestone:** M5 — Polish & ship · **Depends on:** feature-complete strings after E15

## Owner summary

E16 translates a finished, stable user interface rather than chasing strings while major features are still changing. It runs after the macOS 1.0 feature-complete gate and E15's whole-app polish so translators work against the interface we actually intend to ship.

The goal is not to maximise locale count at any cost. The goal is a reliable String Catalog pipeline, complete English source strings, a small set of well-tested priority locales, and a workflow the community can extend safely.

## Problem

The legacy app has many translations, but carrying them over blindly would preserve stale terminology and create large rework if the new product's UI is still moving. New math/diagram/error states also introduce strings that must be designed accessibly before translation.

## Representative user journeys

1. Launch the complete app in a shipped non-English locale and use normal Markdown, math, diagram, file and settings flows without obvious untranslated UI or clipped layouts.
2. Trigger an error/diagnostic state and receive translated user-facing guidance while technical source text remains unchanged.
3. Change locale and retain correct pluralisation, menu structure, keyboard shortcuts and document behaviour.
4. Add/update a translation through the documented Transifex workflow without hand-editing generated build artefacts.

## Scope

- All user-facing UI strings through String Catalogs (`.xcstrings`); no new hard-coded UI strings.
- Pluralisation through catalog variations.
- Transifex project/configuration and a documented push/pull workflow suitable for the new product.
- Port priority locales first: `ja`, `zh-Hans`, `zh-Hant`, `de`, `fr`, `es`, `ko-KR`, subject to actual contributor/quality availability at implementation time.
- Pseudo-localisation and layout QA across the complete macOS 1.0 UI, including math/diagram diagnostics, command palette, settings and release-facing screens.
- Fallback behaviour for missing/partial translations must be deliberate and documented.

## Explicit non-goals

- Translating planning documents, source-code comments or the marketing website.
- Claiming all legacy MacDown locales are complete for 1.0 without actual translation/QA evidence.
- Starting localisation before feature strings are stable.

## User-visible acceptance criteria

- [ ] String audit finds no unintended hard-coded user-facing UI strings.
- [ ] Pluralised strings are correct in at least three materially different plural-rule languages.
- [ ] The complete app can be exercised in at least one shipped non-English locale without release-blocking clipping, truncation or untranslated critical UI.
- [ ] Math/diagram/error/recovery states use the same localisation pipeline as ordinary editor UI.
- [ ] Pseudo-localisation exposes no unresolved release-blocking layout failures.
- [ ] Translation sync/update process is documented in language a maintainer can follow without agent context.

## Release placement

E16 follows E15 and stable macOS 1.0 strings. It precedes E17 so release notes, first-run UI and distribution-facing copy can be checked against the final shipped locales.

## Architecture gate

E16 must satisfy `planning/EPIC_STANDARD.md` before implementation begins. Its architecture should reconcile the actual current String Catalog state, final product name, string inventory and the practical Transifex workflow rather than copying the legacy app's locale list mechanically.
