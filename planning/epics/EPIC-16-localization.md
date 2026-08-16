> **Title:** [EPIC-16] Localization: String Catalogs + Transifex migration
> **Labels:** `epic`, `polish` · **Milestone:** M5 — Polish & ship · **Depends on:** feature-complete identity + E15 final in-app UI/copy

## Owner summary

E16 translates a finished, stable user interface rather than chasing strings while major features or branding are still changing. It runs only after the public product identity is frozen at the feature-complete gate and E15 has finalised the in-app first-run/onboarding experience.

The goal is not to maximise locale count at any cost. The goal is a reliable String Catalog pipeline, complete English source strings, a small set of well-tested priority locales, and a workflow the community can extend safely.

E16 is the **in-app string freeze** for macOS 1.0. E17 may still write release notes/website copy, but it must not quietly add new application UI or user-facing app strings after this point without reopening localisation verification.

## Problem

The legacy app has many translations, but carrying them over blindly would preserve stale terminology and create rework if the new product's name, first-run flow or technical-content diagnostics are still moving. Math/diagram/error states also introduce strings that must be designed accessibly before translation.

## Representative user journeys

1. Launch the complete app under the final product identity in a shipped non-English locale and use normal Markdown, math, diagram, file, first-run and settings flows without obvious untranslated UI or clipped layouts.
2. Trigger an error/diagnostic state and receive translated user-facing guidance while technical source text remains unchanged.
3. Change locale and retain correct pluralisation, menu structure, keyboard shortcuts and document behaviour.
4. Add/update a translation through the documented Transifex workflow without hand-editing generated build artefacts.
5. Build E17 release candidates without discovering an English-only app screen introduced after localisation was declared complete.

## Preconditions

- Final public product name/identity used by the app is frozen.
- E15 final first-run/sample/onboarding UI and app copy are complete enough to freeze.
- Known P0/P1 app-UI blockers from the feature-complete/E15 gates are resolved.

## Scope

- All user-facing UI strings through String Catalogs (`.xcstrings`); no new hard-coded UI strings.
- Pluralisation through catalog variations.
- Transifex project/configuration and a documented push/pull workflow suitable for the new product.
- Port priority locales first: `ja`, `zh-Hans`, `zh-Hant`, `de`, `fr`, `es`, `ko-KR`, subject to actual contributor/quality availability at implementation time.
- Pseudo-localisation and layout QA across the complete macOS 1.0 UI, including first-run/onboarding, math/diagram diagnostics, command palette, settings and release-facing in-app screens.
- Fallback behaviour for missing/partial translations must be deliberate and documented.
- Record the string-freeze baseline used by E17.

## String-freeze rule

After E16 sign-off:

- E17 may change non-app release notes, README/website/landing copy and packaging metadata as needed;
- E17 must not introduce new user-facing application strings or a new app screen without updating the String Catalog and rerunning the affected localisation/pseudo-localisation checks;
- emergency in-app wording fixes are allowed only with that explicit re-verification;
- developer logs/debug-only strings do not count as user-facing UI unless surfaced in normal app flows.

## Explicit non-goals

- Translating planning documents, source-code comments or the marketing website.
- Claiming all legacy MacDown locales are complete for 1.0 without actual translation/QA evidence.
- Starting localisation before identity and first-run/app UI are stable.

## User-visible acceptance criteria

- [ ] Final product name/identity is consistently represented in shipped app strings before translation sign-off.
- [ ] String audit finds no unintended hard-coded user-facing UI strings.
- [ ] Pluralised strings are correct in at least three materially different plural-rule languages.
- [ ] The complete app, including first-run/onboarding, can be exercised in at least one shipped non-English locale without release-blocking clipping, truncation or untranslated critical UI.
- [ ] Math/diagram/error/recovery states use the same localisation pipeline as ordinary editor UI.
- [ ] Pseudo-localisation exposes no unresolved release-blocking layout failures.
- [ ] Translation sync/update process is documented in language a maintainer can follow without agent context.
- [ ] E17 can identify the exact string-freeze baseline and knows that new in-app strings require localisation re-verification.

## Release placement

E16 follows the feature-complete identity freeze and E15's final in-app UI/copy pass. It precedes E17 so distribution/release work packages a localised application rather than creating new app experiences afterward.

## Architecture gate

E16 must satisfy `planning/EPIC_STANDARD.md` and `planning/RELEASE_HARDENING.md`. Its architecture should reconcile the actual current String Catalog state, final product name, final first-run/onboarding UI, complete string inventory and practical Transifex workflow rather than copying the legacy locale list mechanically.
