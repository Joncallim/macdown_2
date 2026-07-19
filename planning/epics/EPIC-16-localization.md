> **Title:** [EPIC-16] Localization: String Catalogs + Transifex migration
> **Labels:** `epic`, `polish` · **Milestone:** M5 — Polish & ship · **Depends on:** stable strings (run late)

## Context

Old app: 25 locales via `.strings` files + Transifex. New product starts with
English + String Catalogs (`.xcstrings`), then ports high-value locales.

## Scope

- All UI strings via String Catalogs; string audit (no hardcoded UI text)
- Pluralization via catalog variations (replaces JJPluralForm)
- Transifex project for the new product; push/pull CI job (like the old
  Travis step, now GitHub Actions)
- Port priority locales first (ja, zh-Hans, zh-Hant, de, fr, es, ko-KR —
  matching the old app's test-mirrored set), community contributors do the rest
- Pseudo-localization run to catch layout breakage

## Deliverables

1. `.xcstrings` catalogs covering 100% of UI strings
2. Transifex config + CI sync job
3. Locale QA checklist + pseudo-loc screenshots pass

## Acceptance criteria

- [ ] String audit finds zero hardcoded UI strings
- [ ] Pluralized strings (word/char counts) correct in ≥ 3 plural-rule languages
- [ ] App runs fully in one non-English shipped locale without layout breakage
- [ ] CI fails on untranslated-string regressions above an agreed threshold

## Out of scope

Translating the planning docs / website.

## Notes

Run this as late as possible — strings churn heavily before M5.
