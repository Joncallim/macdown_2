#!/usr/bin/env python3
"""Inventory and structurally validate the repository's XCStrings catalogs.

This is deliberately a static, hermetic audit aid.  It reports only evidence
available in the checkout: catalog structure, package resource declarations,
and direct literal call sites.  It does not extract strings, compile catalogs,
choose plural forms, assess translation quality, or claim native review.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import re
import sys
from typing import Any


SCHEMA = 1
PRINTF = re.compile(r"%(?:(?P<position>\d+)\$)?(?P<type>@|lld|ld|d|f|g|s|u|zu|llu|lf)")
SUBSTITUTION = re.compile(r"%#@(?P<name>[A-Za-z_]\w*)@")
VARIANT_REFERENCE = re.compile(r"%(?P<name>[A-Za-z_][A-Za-z0-9_]*)")
DIRECT_CALL = re.compile(r"(?:String|AttributedString)\s*\(\s*localized:\s*\"(?P<key>(?:\\.|[^\"\\])*)\"", re.S)


class CatalogError(ValueError):
    """A catalog cannot provide reliable structural evidence."""


def repo_relative(repo: Path, path: Path) -> str:
    return path.relative_to(repo).as_posix()


def load_catalog(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise CatalogError(f"{path}: malformed JSON: {error}") from error
    if not isinstance(value, dict) or not isinstance(value.get("strings"), dict):
        raise CatalogError(f"{path}: expected an object with a strings object")
    return value


def printf_signature(value: str) -> list[str]:
    """Return printf argument types in argument order; escaped %% is ignored."""
    signature: list[str] = []
    index = 0
    while index < len(value):
        if value[index:index + 2] == "%%":
            index += 2
            continue
        match = PRINTF.match(value, index)
        if match:
            signature.append(match.group("type"))
            index = match.end()
        else:
            index += 1
    return signature


def catalog_target(repo: Path, catalog: Path) -> tuple[str, str, Path | None]:
    relative = repo_relative(repo, catalog)
    if relative == "MacDown2/MacDown2/Localizable.xcstrings":
        return "MacDown2", "Bundle.main (project target resource)", repo / "MacDown2/MacDown2"
    parts = catalog.parts
    try:
        source_index = parts.index("Sources")
        target = parts[source_index + 1]
    except (ValueError, IndexError):
        return "unknown", "unknown (path is not a known app/package resource)", None
    manifest = repo / "MacDown2/Packages/MacDownKit/Package.swift"
    declaration = manifest.read_text(encoding="utf-8") if manifest.exists() else ""
    resource_pattern = re.compile(r"\.target\(\s*name:\s*\"" + re.escape(target) + r"\"[\s\S]{0,1000}?resources:\s*\[\.process\(\"Resources\"\)\]")
    bundle = "Bundle.module (SwiftPM processed resource)" if resource_pattern.search(declaration) else "unknown (no matching SwiftPM resource declaration)"
    return target, bundle, catalog.parents[1]


def direct_callsites(source_root: Path | None, key: str, repo: Path) -> list[str]:
    if source_root is None or not source_root.exists():
        return []
    found: list[str] = []
    for source in sorted(source_root.rglob("*.swift")):
        text = source.read_text(encoding="utf-8")
        for match in DIRECT_CALL.finditer(text):
            # Compare source spelling so Swift interpolation remains deliberately
            # unsupported evidence instead of being incorrectly decoded as JSON.
            swift_spelling = key.replace("\\", "\\\\").replace('"', '\\"')
            if match.group("key") == swift_spelling:
                line = text.count("\n", 0, match.start()) + 1
                found.append(f"{repo_relative(repo, source)}:{line}")
    return found


def variants(localization: dict[str, Any]) -> dict[str, list[str]]:
    result: dict[str, list[str]] = {}
    for name, substitution in sorted(localization.get("substitutions", {}).items()):
        variation = substitution.get("variations", {}) if isinstance(substitution, dict) else {}
        plural = variation.get("plural", {}) if isinstance(variation, dict) else {}
        if isinstance(plural, dict):
            result[name] = sorted(plural)
    return result


def inventory(repo: Path) -> dict[str, Any]:
    entries: list[dict[str, Any]] = []
    for catalog_path in sorted(repo.glob("MacDown2/**/*.xcstrings")):
        catalog = load_catalog(catalog_path)
        target, bundle, source_root = catalog_target(repo, catalog_path)
        for key, entry in sorted(catalog["strings"].items()):
            if not isinstance(entry, dict):
                raise CatalogError(f"{catalog_path}: {key!r} is not a string entry")
            localizations = entry.get("localizations", {})
            if not isinstance(localizations, dict):
                raise CatalogError(f"{catalog_path}: {key!r} localizations is not an object")
            locale_states = {
                locale: localization.get("stringUnit", {}).get("state", "unknown")
                for locale, localization in sorted(localizations.items())
                if isinstance(localization, dict)
            }
            callsites = direct_callsites(source_root, key, repo)
            entries.append({
                "target": target,
                "catalog": repo_relative(repo, catalog_path),
                "bundle": bundle,
                "key": key,
                "source_default_value": key,
                "required_locales": ["fr", "ja", "pl"],
                "required_locale_evidence": "planning/downstream/issue-17-handoff.md: retain established three plural-family verification locales",
                "interpolation": {
                    "printf_argument_types": printf_signature(key),
                    "contains_inflection_markup": "(inflect:" in key,
                },
                "variants": {locale: variants(value) for locale, value in sorted(localizations.items()) if isinstance(value, dict)},
                "locale_states": locale_states,
                "callsites": callsites,
                "callsite_evidence": "direct_literal_static_match" if callsites else "unknown_or_nonliteral_static_callsite",
                "review_state": "unknown_no_native_review_record_in_checkout",
            })
    return {
        "schema": SCHEMA,
        "scope": "catalog-backed product strings only; excludes authored document text and stable engine codes by construction",
        "limitations": [
            "Static call sites include only direct String/AttributedString localized literals; nonliteral and SwiftUI extraction evidence is unknown.",
            "Translation quality, native-speaker review, runtime resolution, catalog compilation, CLDR behavior, and layout acceptance are not evaluated.",
        ],
        "entries": entries,
    }


def validate_localization(catalog_path: Path, key: str, locale: str, value: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    unit = value.get("stringUnit")
    if not isinstance(unit, dict) or not isinstance(unit.get("value"), str):
        return errors  # An untranslated locale is inventory evidence, not malformed structure.
    translated = unit["value"]
    source_signature = printf_signature(key)
    substitutions = value.get("substitutions", {})
    if not isinstance(substitutions, dict):
        return [f"{catalog_path}:{key!r}:{locale}: substitutions is not an object"]
    if substitutions:
        ordered: list[tuple[int, str, str]] = []
        for name, substitution in substitutions.items():
            if not isinstance(substitution, dict) or not isinstance(substitution.get("argNum"), int) or not isinstance(substitution.get("formatSpecifier"), str):
                errors.append(f"{catalog_path}:{key!r}:{locale}: malformed substitution {name!r}")
                continue
            ordered.append((substitution["argNum"], name, substitution["formatSpecifier"]))
            plural = substitution.get("variations", {}).get("plural", {}) if isinstance(substitution.get("variations", {}), dict) else {}
            if plural:
                if not isinstance(plural, dict) or "other" not in plural:
                    errors.append(f"{catalog_path}:{key!r}:{locale}: plural substitution {name!r} lacks an other variant")
                    continue
                for category, variant in plural.items():
                    variant_value = variant.get("stringUnit", {}).get("value") if isinstance(variant, dict) else None
                    if not isinstance(variant_value, str):
                        errors.append(f"{catalog_path}:{key!r}:{locale}: plural {name!r}/{category!r} lacks a string value")
                    else:
                        # XCStrings emits %arg for a substitution named arg1.
                        # Preserve that convention rather than assuming the catalog
                        # repeats the numeric argument suffix in every variant.
                        variant_name = re.sub(r"\d+$", "", name)
                        if variant_name not in VARIANT_REFERENCE.findall(variant_value):
                            errors.append(f"{catalog_path}:{key!r}:{locale}: plural {name!r}/{category!r} omits %{variant_name}")
        ordered.sort()
        actual_signature = [specifier for _, _, specifier in ordered]
        if actual_signature != source_signature:
            errors.append(f"{catalog_path}:{key!r}:{locale}: substitution types {actual_signature} do not match source {source_signature}")
        expected_refs = {name for _, name, _ in ordered}
        actual_refs = set(SUBSTITUTION.findall(translated))
        if actual_refs != expected_refs:
            errors.append(f"{catalog_path}:{key!r}:{locale}: substitution references {sorted(actual_refs)} do not match {sorted(expected_refs)}")
    else:
        translated_signature = printf_signature(translated)
        if translated_signature != source_signature:
            errors.append(f"{catalog_path}:{key!r}:{locale}: placeholders {translated_signature} do not match source {source_signature}")
    return errors


def validate(repo: Path) -> list[str]:
    errors: list[str] = []
    for path in sorted(repo.glob("MacDown2/**/*.xcstrings")):
        catalog = load_catalog(path)
        for key, entry in catalog["strings"].items():
            if not isinstance(entry, dict):
                errors.append(f"{path}:{key!r}: string entry is not an object")
                continue
            localizations = entry.get("localizations", {})
            if not isinstance(localizations, dict):
                errors.append(f"{path}:{key!r}: localizations is not an object")
                continue
            for locale, localization in localizations.items():
                if not isinstance(localization, dict):
                    errors.append(f"{path}:{key!r}:{locale}: localization is not an object")
                else:
                    errors.extend(validate_localization(path, key, locale, localization))
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument("--inventory-out", type=Path, help="write deterministic inventory JSON")
    parser.add_argument("--check", action="store_true", help="fail if validation finds structural defects")
    args = parser.parse_args()
    try:
        record = inventory(args.repo)
        errors = validate(args.repo)
    except CatalogError as error:
        print(json.dumps({"status": "invalid", "errors": [str(error)]}, indent=2, sort_keys=True))
        return 1
    if args.inventory_out:
        args.inventory_out.write_text(json.dumps(record, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    payload = {"status": "passed" if not errors else "invalid", "catalogs": len({entry["catalog"] for entry in record["entries"]}), "entries": len(record["entries"]), "errors": errors}
    print(json.dumps(payload, indent=2, ensure_ascii=False, sort_keys=True))
    return 1 if args.check and errors else 0


if __name__ == "__main__":
    sys.exit(main())
