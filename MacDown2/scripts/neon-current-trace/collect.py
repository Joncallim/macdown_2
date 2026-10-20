#!/usr/bin/env python3
"""Trace the fork-pinned release candidate in an isolated locked package copy."""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
import re
from pathlib import Path
import signal
import shlex
import subprocess
import sys
import tarfile
import time
from datetime import datetime, timezone
from typing import Any


BASELINE_COMMIT = "29c3682e93729a5f53a4b67be4d91e052c97444d"
BASE_PACKAGE_TREE = "539be5f230b992b8f5d730650bcb913c560c1ad6"
LOCK_SHA = "c56d3a22690eaba3e48f030bcf5f5bc0b4eb82a5cdb6410b10795ece5c18c22d"
COMMAND_TIMEOUT_SECONDS = 30 * 60
TERMINATE_GRACE_SECONDS = 10
EXPECTED_PIN_COUNT = 22
MAX_TRACE_EVENTS = 32768
MAX_TRACE_PAYLOAD_BYTES = 16 * 1024 * 1024
EXPECTED_TRACE_LABELS = {
    "restore-idle-false", "restore-idle-true", "startup-single-edit", "startup-several-edits",
}
PATCH_DIRECTORY = Path("planning/diagnostics/neon-current-trace")
ALLOWED_PACKAGE_PATCH_PATHS = {
    "MacDownKit/Package.swift",
    "MacDownKit/Tests/HighlightingTests/HighlightingRestoreStartupTests.swift",
    "MacDownKit/Tests/HighlightingTests/HighlightingSizeFallbackTests.swift",
    "MacDownKit/Tests/HighlightingTests/RestoreHostedTraceSupport.swift",
    "MacDownKit/Tests/TextFiltersTests/TextFilterBlockingCleanupDeadlineTests.swift",
    "MacDownKit/Tests/TextFiltersTests/TextFilterFixtureOwnershipSupport.swift",
}


class DiagnosticFailure(RuntimeError):
    """An expected diagnostic precondition or subprocess failed."""


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def git(repo: Path, *args: str, check: bool = True) -> str:
    result = subprocess.run(
        ["git", "-C", str(repo), *args],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if check and result.returncode != 0:
        raise DiagnosticFailure(
            f"git {' '.join(args)} failed ({result.returncode}): {result.stderr.strip()}"
        )
    return result.stdout.rstrip("\n")


def ensure_new_directory(path: Path, label: str) -> Path:
    resolved = path.expanduser().resolve()
    if resolved.exists():
        raise DiagnosticFailure(f"{label} must be a new directory; already exists: {resolved}")
    resolved.mkdir(parents=True)
    return resolved


def is_within(path: Path, parent: Path) -> bool:
    try:
        path.relative_to(parent)
        return True
    except ValueError:
        return False


def normalized_remote(value: str) -> str:
    value = value.strip()
    if value.startswith("git@") and ":" in value:
        host, path = value[4:].split(":", 1)
        value = f"https://{host}/{path}"
    value = value.removesuffix(".git").rstrip("/")
    return value.lower()


def run_command(argv, cwd, log_path, env, records, label):
    """Bound setup/build commands only; the test process uses observed_command."""
    record = {"label": label, "argv": argv, "cwd": str(cwd), "started_at": utc_now(),
              "timeout_seconds": COMMAND_TIMEOUT_SECONDS, "log": str(log_path), "outcome": "running"}
    records.append(record)
    process = None
    try:
        with log_path.open("w", encoding="utf-8", errors="replace") as log:
            log.write("$ " + shlex.join(argv) + "\n")
            log.flush()
            process = subprocess.Popen(argv, cwd=cwd, env=env, stdout=log, stderr=subprocess.STDOUT,
                                       text=True, start_new_session=True)
            record["pid"] = process.pid
            try:
                record["exit_code"] = process.wait(timeout=COMMAND_TIMEOUT_SECONDS)
                record["outcome"] = "passed" if record["exit_code"] == 0 else "failed"
            except subprocess.TimeoutExpired:
                record["outcome"] = "timed_out"
                record["process_group_cleanup"] = terminate_owned_process_group(process)
                record["exit_code"] = process.poll()
    except Exception as error:
        record["outcome"] = "launch_failed"
        record["error"] = f"{type(error).__name__}: {error}"
        raise
    finally:
        record["ended_at"] = utc_now()
        if process is not None and process.poll() is None:
            record["process_group_cleanup"] = terminate_owned_process_group(process)
        if log_path.exists():
            record["log_sha256"] = sha256_file(log_path)
    if record["outcome"] != "passed":
        raise DiagnosticFailure(f"{label} {record['outcome']} (exit={record.get('exit_code')}); see {log_path}")
    return record


def terminate_owned_process_group(process: subprocess.Popen[Any]) -> dict[str, str]:
    if process.poll() is not None:
        return {
            "outcome": "parent_already_exited_no_signal",
            "detail": "Skipped group signal to avoid a potentially reused process-group ID",
        }
    try:
        process_group = os.getpgid(process.pid)
    except ProcessLookupError:
        return {"outcome": "leader_missing_before_signal"}
    if process_group != process.pid:
        return {"outcome": "unexpected_process_group", "process_group": str(process_group)}
    try:
        os.killpg(process_group, signal.SIGTERM)
    except ProcessLookupError:
        return {"outcome": "group_missing_before_signal"}

    try:
        process.wait(timeout=TERMINATE_GRACE_SECONDS)
        return {
            "outcome": "sigterm_sent_to_verified_live_group",
            "detail": "Leader exited after SIGTERM; descendant completion was not independently observed",
        }
    except subprocess.TimeoutExpired:
        try:
            if process.poll() is None and os.getpgid(process.pid) == process_group:
                os.killpg(process_group, signal.SIGKILL)
                process.wait()
                return {"outcome": "sigkill_sent_to_verified_live_group"}
        except ProcessLookupError:
            return {"outcome": "leader_or_group_gone_before_sigkill"}
        return {
            "outcome": "leader_exited_before_sigkill",
            "detail": "Skipped SIGKILL because the original group identity could not be verified",
        }


def archive_packages(repo: Path, workspace: Path, output: Path, run: dict[str, Any]) -> Path:
    archive_path = workspace / "source-packages.tar"
    command = ["git", "-C", str(repo), "archive", "--format=tar", "HEAD", "MacDown2/Packages"]
    record: dict[str, Any] = {
        "label": "export_committed_packages",
        "argv": command,
        "cwd": str(repo),
        "started_at": utc_now(),
        "outcome": "running",
        "log": str(output / "export-packages.log"),
    }
    run["commands"].append(record)
    process: subprocess.Popen[bytes] | None = None
    try:
        with (output / "export-packages.log").open("w", encoding="utf-8") as log:
            log.write(f"$ {' '.join(command)} > {archive_path}\n")
            log.flush()
            with archive_path.open("wb") as archive_stream:
                process = subprocess.Popen(
                    command,
                    stdout=archive_stream,
                    stderr=log,
                    start_new_session=True,
                )
                record["pid"] = process.pid
                try:
                    exit_code = process.wait(timeout=COMMAND_TIMEOUT_SECONDS)
                    record["outcome"] = "passed" if exit_code == 0 else "failed"
                except subprocess.TimeoutExpired:
                    record["outcome"] = "timed_out"
                    record["timed_out"] = True
                    record["process_group_cleanup"] = terminate_owned_process_group(process)
                    exit_code = process.poll()
                    log.write(f"\n[runner] timed out after {COMMAND_TIMEOUT_SECONDS} seconds\n")
                    log.flush()
    except Exception as error:
        record["outcome"] = "launch_failed"
        record["error"] = f"{type(error).__name__}: {error}"
        raise
    finally:
        record["ended_at"] = utc_now()
        if process is not None and "process_group_cleanup" not in record:
            if process.poll() is None:
                record["process_group_cleanup"] = terminate_owned_process_group(process)
            else:
                record["process_group_cleanup"] = {
                    "outcome": "parent_already_exited_no_signal",
                    "detail": "Skipped group signal to avoid a potentially reused process-group ID",
                }
        log_path = output / "export-packages.log"
        if log_path.exists():
            record["log_sha256"] = sha256_file(log_path)
    record["exit_code"] = exit_code
    if record["outcome"] != "passed":
        raise DiagnosticFailure(f"git archive {record['outcome']} ({exit_code}); see {record['log']}")
    record["archive_sha256"] = sha256_file(archive_path)
    record["archive_size_bytes"] = archive_path.stat().st_size
    record["archive_path"] = str(archive_path)
    with tarfile.open(archive_path, "r:") as archive:
        archive.extractall(workspace, filter="data")
    return workspace / "MacDown2" / "Packages"


def read_pins(resolved_file: Path) -> list[dict[str, Any]]:
    payload = json.loads(resolved_file.read_text(encoding="utf-8"))
    pins = payload.get("pins")
    if not isinstance(pins, list) or not pins:
        raise DiagnosticFailure(f"No pins found in {resolved_file}")
    return pins


def source_attestation(repo: Path, expected_head: str | None = None, expected_tree: str | None = None) -> dict[str, Any]:
    try:
        head = git(repo, "rev-parse", "HEAD")
        tree = git(repo, "rev-parse", "HEAD^{tree}")
        source_status = git(repo, "status", "--porcelain", "--untracked-files=all")
        package_status = git(
            repo,
            "status",
            "--porcelain",
            "--untracked-files=all",
            "--",
            "MacDown2/Packages",
        )
        package_tree = git(repo, "rev-parse", "HEAD:MacDown2/Packages")
        git(repo, "merge-base", "--is-ancestor", BASELINE_COMMIT, head)
        package_diff_empty = package_tree == BASE_PACKAGE_TREE
        matches_expected = (expected_head is None or head == expected_head) and (
            expected_tree is None or tree == expected_tree
        )
        clean = not source_status and not package_status
        outcome = package_diff_empty and matches_expected and clean
        return {
            "outcome": "passed" if outcome else "failed",
            "head_sha": head,
            "tree_sha": tree,
            "expected_head_matches": expected_head is None or head == expected_head,
            "expected_tree_matches": expected_tree is None or tree == expected_tree,
            "baseline_commit": BASELINE_COMMIT,
            "baseline_ancestor": True,
            "package_tree": package_tree,
            "expected_package_tree": BASE_PACKAGE_TREE,
            "baseline_package_diff_empty": package_diff_empty,
            "source_worktree_clean": not bool(source_status),
            "package_worktree_clean": not bool(package_status),
            "source_status": source_status,
            "package_status": package_status,
        }
    except Exception as error:
        return {"outcome": "failed", "error": f"{type(error).__name__}: {error}"}


def github_pull_request_identity() -> dict[str, str] | None:
    event_path = os.environ.get("GITHUB_EVENT_PATH")
    if not event_path:
        return None
    payload = json.loads(Path(event_path).read_text(encoding="utf-8"))
    pull_request = payload.get("pull_request")
    if not isinstance(pull_request, dict):
        return None
    head = pull_request.get("head", {})
    base = pull_request.get("base", {})
    if not isinstance(head, dict) or not isinstance(base, dict):
        raise DiagnosticFailure("GitHub pull request event has malformed head/base fields")
    return {
        "head_sha": str(head.get("sha", "")),
        "head_ref": str(head.get("ref", "")),
        "base_sha": str(base.get("sha", "")),
        "base_ref": str(base.get("ref", "")),
        "event_merge_sha": str(pull_request.get("merge_commit_sha") or ""),
    }


def validate_github_event(event_name: str | None, event_path: str | None, event_pr: dict[str, str] | None, head: str) -> None:
    if event_name not in (None, "", "pull_request", "workflow_dispatch"):
        raise DiagnosticFailure(f"Unsupported GitHub event: {event_name}")
    if event_name == "pull_request" and (not event_path or event_pr is None):
        raise DiagnosticFailure("GitHub pull request event did not contain a pull request identity")
    if event_name in ("pull_request", "workflow_dispatch") and os.environ.get("GITHUB_SHA") != head:
        raise DiagnosticFailure("Checked-out HEAD differs from the dispatched GitHub SHA")
    if event_pr is not None and any(not event_pr[field] for field in ("head_sha", "base_sha", "head_ref", "base_ref")):
        raise DiagnosticFailure("GitHub pull request event is missing head/base SHA or ref")


def checkout_origin(checkout: Path, repository_root: Path) -> str:
    """Follow SwiftPM's local bare-repository origin, confined to this workspace."""
    current = checkout
    visited: set[Path] = set()
    for _ in range(4):
        remote = git(current, "remote", "get-url", "origin")
        if remote.startswith(("https://", "ssh://", "git@")):
            return remote
        candidate = Path(remote)
        if not candidate.is_absolute():
            candidate = current / candidate
        candidate = candidate.resolve()
        if (
            candidate in visited
            or not is_within(candidate, repository_root.resolve())
            or not candidate.is_dir()
            or git(candidate, "rev-parse", "--is-bare-repository") != "true"
        ):
            raise DiagnosticFailure(f"Unexpected SwiftPM local origin for {checkout.name}")
        visited.add(candidate)
        current = candidate
    raise DiagnosticFailure(f"SwiftPM origin chain is too deep for {checkout.name}")


def audit_checkouts(package_dir: Path, pins: list[dict[str, Any]]) -> list[dict[str, str]]:
    checkout_root = package_dir / "MacDownKit" / ".build" / "checkouts"
    if not checkout_root.is_dir():
        raise DiagnosticFailure(f"SwiftPM checkout directory is missing: {checkout_root}")

    checkouts: dict[str, Path] = {}
    for candidate in checkout_root.iterdir():
        if candidate.is_dir() and (candidate / ".git").exists():
            remote = checkout_origin(candidate, checkout_root.parent / "repositories")
            if remote:
                checkouts[normalized_remote(remote)] = candidate

    audited: list[dict[str, str]] = []
    missing: list[str] = []
    dirty: list[str] = []
    mismatched: list[str] = []
    for pin in pins:
        identity = str(pin.get("identity", ""))
        location = str(pin.get("location", ""))
        state = pin.get("state", {})
        expected_revision = str(state.get("revision", ""))
        checkout = checkouts.get(normalized_remote(location))
        if checkout is None:
            missing.append(identity or location)
            continue
        actual_revision = git(checkout, "rev-parse", "HEAD")
        status = git(checkout, "status", "--porcelain", "--untracked-files=all")
        if actual_revision != expected_revision:
            mismatched.append(f"{identity}: expected {expected_revision}, got {actual_revision}")
        if status:
            dirty.append(identity)
        audited.append(
            {
                "identity": identity,
                "location": location,
                "expected_revision": expected_revision,
                "actual_revision": actual_revision,
                "checkout": str(checkout),
                "clean": str(not bool(status)).lower(),
            }
        )
    if missing or dirty or mismatched:
        raise DiagnosticFailure(
            "Locked checkout audit failed: "
            f"missing={missing}, dirty={dirty}, revision_mismatches={mismatched}"
        )
    if len(audited) != len(pins):
        raise DiagnosticFailure(f"Audited {len(audited)} of {len(pins)} locked pins")
    return audited


def audit_post_diagnostic_checkouts(
    package_dir: Path,
    pins: list[dict[str, Any]],
    neon_paths: set[str],
) -> list[dict[str, str]]:
    audited = audit_checkouts_allowing_neon_patch(package_dir, pins, neon_paths)
    if len(audited) != EXPECTED_PIN_COUNT:
        raise DiagnosticFailure(f"Post-test audit covered {len(audited)} of {EXPECTED_PIN_COUNT} pins")
    return audited


def audit_checkouts_allowing_neon_patch(
    package_dir: Path,
    pins: list[dict[str, Any]],
    neon_paths: set[str],
) -> list[dict[str, str]]:
    checkout_root = package_dir / "MacDownKit" / ".build" / "checkouts"
    audited: list[dict[str, str]] = []
    missing: list[str] = []
    dirty: list[str] = []
    mismatched: list[str] = []
    for pin in pins:
        identity = str(pin.get("identity", ""))
        location = str(pin.get("location", ""))
        expected_revision = str(pin.get("state", {}).get("revision", ""))
        checkout = next(
            (
                candidate
                for candidate in checkout_root.iterdir()
                if candidate.is_dir()
                and (candidate / ".git").exists()
                and normalized_remote(checkout_origin(candidate, checkout_root.parent / "repositories"))
                == normalized_remote(location)
            ),
            None,
        )
        if checkout is None:
            missing.append(identity or location)
            continue
        actual_revision = git(checkout, "rev-parse", "HEAD")
        status = git(checkout, "status", "--porcelain", "--untracked-files=all")
        if actual_revision != expected_revision:
            mismatched.append(f"{identity}: expected {expected_revision}, got {actual_revision}")
        if status:
            status_paths = {line[3:] for line in status.splitlines() if len(line) >= 4}
            if identity.casefold() != "neon" or status_paths != neon_paths:
                dirty.append(identity)
        audited.append(
            {
                "identity": identity,
                "location": location,
                "expected_revision": expected_revision,
                "actual_revision": actual_revision,
                "checkout": str(checkout),
                "clean_or_expected_neon_patch": str(not bool(status) or identity.casefold() == "neon").lower(),
            }
        )
    if missing or dirty or mismatched:
        raise DiagnosticFailure(
            "Post-test locked checkout audit failed: "
            f"missing={missing}, unexpected_dirty={dirty}, revision_mismatches={mismatched}"
        )
    return audited


def locate_test_bundle(package_root: Path) -> Path:
    candidates = sorted(
        path.resolve()
        for path in (package_root / ".build").rglob("MacDownKitPackageTests.xctest")
        if path.is_dir()
    )
    if len(candidates) != 1:
        raise DiagnosticFailure(
            "Expected exactly one isolated MacDownKitPackageTests.xctest bundle after build; "
            f"found {len(candidates)}: {[str(path) for path in candidates]}"
        )
    return candidates[0]


def trace_range(value):
    match = re.fullmatch(r"\{(\d+),\s*(\d+)\}", value)
    if match is None:
        raise DiagnosticFailure("Malformed trace range")
    return tuple(map(int, match.groups()))


def trace_tokens(value):
    result = []
    for token in value.split("|") if value else []:
        match = re.fullmatch(r"([^:|]+):(\{\d+,\s*\d+\})", token)
        if match is None:
            raise DiagnosticFailure("Malformed ordered token stream")
        result.append((match[1], trace_range(match[2])))
    return result


def require_fields(row, names):
    if not set(names).issubset(row):
        raise DiagnosticFailure("Required trace payload missing from " + row["event"])


def validate_application_events(events, label):
    """Reject incomplete/corrupt attribution without treating style mismatch as corruption."""
    bindings = {}
    for row in events:
        if row.get("event") == "client.bind":
            require_fields(row, {"client", "tree", "generation", "view", "role", "callbackContext"})
            if (not all(row[k] for k in ("client", "tree", "view", "callbackContext"))
                    or not row["generation"].isdigit() or int(row["generation"]) < 1
                    or row["client"] in bindings):
                raise DiagnosticFailure("Incomplete or duplicate client/tree/generation binding")
            bindings[row["client"]] = row
    sequences = [int(r["sequence"]) for r in events]
    if sequences != sorted(set(sequences)):
        raise DiagnosticFailure("Trace sequences are duplicate or unordered")
    by_query = {}
    for row in events:
        if row.get("queryID") not in {None, "0"}:
            by_query.setdefault(row["queryID"], []).append(row)
        if row["event"] in {"paint.before", "paint.after"}:
            require_fields(row, {"renderedRuns", "renderedSHA256", "renderingAvailable"})
        if row["event"] == "fixture.runs":
            require_fields(row, {"observed", "observedSHA256", "reference", "referenceSHA256"})
        for data, digest in (("renderedRuns", "renderedSHA256"), ("observed", "observedSHA256"),
                             ("reference", "referenceSHA256"), ("tokens", "tokensSHA256"),
                             ("namedRanges", "namedRangesSHA256")):
            if data in row and row.get(digest) != hashlib.sha256(row[data].encode()).hexdigest():
                raise DiagnosticFailure("Trace payload hash mismatch")
    applications = [r for r in events if r.get("event") == "query.application"]
    if not applications or not any(r.get("event") == "paint.set.returned" for r in events):
        raise DiagnosticFailure("Trace lacks an actual application/setter observation")
    for application in applications:
        require_fields(application, {"queryID", "queryClient", "tokens", "tokensSHA256", "tokenCount", "action", "clearRange"})
        query = by_query[application["queryID"]]
        client = application["queryClient"]
        if client not in bindings or int(bindings[client]["sequence"]) >= int(application["sequence"]):
            raise DiagnosticFailure("Application lacks prior immutable client binding")
        tokens = trace_tokens(application["tokens"])
        if (not application["tokenCount"].isdigit() or int(application["tokenCount"]) != len(tokens)
                or application["action"] not in {"apply", "replace"}):
            raise DiagnosticFailure("Invalid application action or token count")
        clear = None if application["clearRange"] == "nil" else trace_range(application["clearRange"])
        names = [r["event"] for r in query]
        required = ["query.begin", "query.application", "paint.before", "paint.begin", "paint.end",
                    "paint.after", "query.applied", "query.end"]
        if any(names.count(name) != 1 for name in required):
            raise DiagnosticFailure("Application lacks a unique begin/end/rendering boundary")
        if [names.index(name) for name in required] != sorted(names.index(name) for name in required):
            raise DiagnosticFailure("Application boundary ordering is invalid")
        setters = []
        for index, row in enumerate(query):
            if row["event"] != "query.begin" and row.get("queryClient") != client:
                raise DiagnosticFailure("Query event has a different or absent client binding")
            if row["event"] in {"paint.before", "paint.after"} and row["renderingAvailable"] != "true":
                raise DiagnosticFailure("Rendering attributes unavailable for a recorded application")
            if row["event"] in {"query.application", "paint.begin", "paint.end"}:
                require_fields(row, {"currentVersion", "admittedVersion", "textSHA256"})
                if not row["currentVersion"] or not row["admittedVersion"] or not re.fullmatch(r"[0-9a-f]{64}", row["textSHA256"]):
                    raise DiagnosticFailure("Malformed application version/content attribution")
            if row["event"].startswith("paint.set."):
                require_fields(row, {"requestedRange", "clampedRange", "attributes", "contentLength"})
                if row["event"] not in {"paint.set.returned", "paint.set.rejected"} or not row["contentLength"].isdigit():
                    raise DiagnosticFailure("Invalid setter result")
                requested, clamped = trace_range(row["requestedRange"]), trace_range(row["clampedRange"])
                if sum(clamped) > int(row["contentLength"]):
                    raise DiagnosticFailure("Setter clamp lies beyond recorded content")
                if not names.index("paint.begin") < index < names.index("paint.end"):
                    raise DiagnosticFailure("Setter lies outside its application")
                setters.append(requested)
            if row["event"] == "query.namedRanges":
                require_fields(row, {"namedRanges", "namedRangesSHA256", "range", "clientVersion"})
                trace_tokens(row["namedRanges"])
                trace_range(row["range"])
                if not row["clientVersion"]:
                    raise DiagnosticFailure("Provider version is missing")
        expected_setters = ([clear] if clear is not None else []) + [r for _, r in tokens]
        if setters != expected_setters:
            raise DiagnosticFailure("Application clear/token setter sequence is incomplete or reordered")
        if names.count("query.namedRanges") != 1 and names.count("query.error") != 1:
            raise DiagnosticFailure("Application lacks unique observed provider output/error")
    runs = [r for r in events if r.get("event") == "fixture.runs"]
    oracles = [r for r in runs if r.get("stage") == "oracle"]
    if len(oracles) != 1 or oracles[0].get("originalComparisonMatches") not in {"true", "false"}:
        raise DiagnosticFailure("Missing original primary comparison outcome")
    original = oracles[0]["referenceSHA256"]
    if any(r.get("initialReferenceSHA256") != original or r.get("readOrder") != "afterPrimaryAssertion" for r in runs):
        raise DiagnosticFailure("Primary reference identity/read-order mismatch")
    if oracles[0]["originalComparisonMatches"] == "false" and label.startswith("restore-idle-"):
        stages = [r.get("stage") for r in events if r.get("event") == "fixture.state"]
        expected = ["invalidate.call.begin", "invalidate.call.returned", "discard.call.begin",
                    "discard.call.returned", "rebuild.call.begin", "rebuild.call.returned"]
        if any(stages.count(s) != 1 for s in expected):
            raise DiagnosticFailure("Failed case lacks the existing probe call boundaries")
        if [stages.index(s) for s in expected] != sorted(stages.index(s) for s in expected):
            raise DiagnosticFailure("Probe call boundary ordering is invalid")
        if not {"after2s", "afterInvalidation", "afterRebuild"}.issubset({r.get("stage") for r in runs}):
            raise DiagnosticFailure("Failed case lacks existing probe results")
    if not any(r.get("event") == "styler.validate.returned" for r in events):
        raise DiagnosticFailure("Trace lacks the actual styler validation decision")
    return {"applications": len(applications), "primary_matches": oracles[0]["originalComparisonMatches"],
            "primary_reference_sha256": original}


def validate_traces(trace_dir: Path, helper_pids: set[int]) -> dict[str, Any]:
    json_files = sorted(path for path in trace_dir.iterdir() if path.is_file() and path.suffix == ".json")
    if len(json_files) != len(EXPECTED_TRACE_LABELS):
        raise DiagnosticFailure(
            f"Expected exactly {len(EXPECTED_TRACE_LABELS)} trace JSON files; found {[path.name for path in json_files]}"
        )
    seen_labels: set[str] = set()
    seen_sessions: set[str] = set()
    sessions: list[dict[str, Any]] = []
    for path in json_files:
        try:
            trace = json.loads(path.read_text(encoding="utf-8"))
        except Exception as error:
            raise DiagnosticFailure(f"Unusable trace JSON {path.name}: {type(error).__name__}: {error}") from error
        if not isinstance(trace, dict):
            raise DiagnosticFailure(f"Trace root must be a JSON object: {path.name}")
        label = trace.get("label")
        if trace.get("processID") not in helper_pids:
            raise DiagnosticFailure("Trace process does not match the observed Swift Testing helper")
        session_id = trace.get("session")
        events = trace.get("events")
        dropped = trace.get("droppedEvents")
        payload_bytes = trace.get("payloadBytes")
        if trace.get("schema") != 2:
            raise DiagnosticFailure(f"Unsupported or missing trace schema in {path.name}")
        if label not in EXPECTED_TRACE_LABELS or label in seen_labels:
            raise DiagnosticFailure(f"Unexpected or duplicate trace label {label!r} in {path.name}")
        if not isinstance(session_id, str) or not session_id or session_id in seen_sessions:
            raise DiagnosticFailure(f"Missing or duplicate trace session identity in {path.name}")
        if trace.get("collectionEnded") is not True:
            raise DiagnosticFailure(f"Trace collection did not end cleanly: {path.name}")
        if trace.get("quiescenceAsserted") is not False:
            raise DiagnosticFailure(f"Trace must not claim quiescence: {path.name}")
        if not isinstance(events, list) or len(events) > MAX_TRACE_EVENTS or not all(isinstance(row, dict) for row in events):
            raise DiagnosticFailure(f"Trace events are missing, malformed, or exceed {MAX_TRACE_EVENTS}: {path.name}")
        if not isinstance(dropped, int) or isinstance(dropped, bool) or dropped != 0:
            raise DiagnosticFailure(f"Trace has missing or dropped events ({dropped!r}): {path.name}")
        if (
            not isinstance(payload_bytes, int)
            or isinstance(payload_bytes, bool)
            or payload_bytes < 0
            or payload_bytes > MAX_TRACE_PAYLOAD_BYTES
        ):
            raise DiagnosticFailure(
                f"Trace payloadBytes is missing or exceeds {MAX_TRACE_PAYLOAD_BYTES}: {path.name}"
            )
        if not events or not all(
            all(isinstance(key, str) and isinstance(value, str) for key, value in row.items())
            for row in events
        ):
            raise DiagnosticFailure(f"Trace requires nonempty string-valued event rows: {path.name}")
        actual_bytes = sum(
            len(key.encode("utf-8")) + len(value.encode("utf-8"))
            for row in events for key, value in row.items()
        )
        if actual_bytes != payload_bytes:
            raise DiagnosticFailure(f"Trace payload byte accounting mismatch: {path.name}")
        if events[0].get("event") != "session.start" or events[-1].get("event") != "session.finish":
            raise DiagnosticFailure(f"Trace lacks session start/finish boundaries: {path.name}")
        bindings = {row.get("role") for row in events if row.get("event") == "client.bind"}
        if not {"edited", "fresh"}.issubset(bindings):
            raise DiagnosticFailure(f"Trace lacks edited/fresh client bindings: {path.name}")
        if not any(row.get("event") == "fixture.runs" and row.get("stage") == "oracle" for row in events):
            raise DiagnosticFailure(f"Trace lacks the primary rendered-style oracle: {path.name}")
        attribution = validate_application_events(events, label)
        seen_labels.add(label)
        seen_sessions.add(session_id)
        pending = trace.get("pendingObservedWork")
        if not isinstance(pending, list) or not all(isinstance(item, str) for item in pending):
            raise DiagnosticFailure(f"Malformed pendingObservedWork field in {path.name}")
        sessions.append(
            {
                "file": path.name,
                "process_id": trace["processID"],
                "attribution": attribution,
                "label": label,
                "session": session_id,
                "event_count": len(events),
                "dropped_events": dropped,
                "payload_bytes": payload_bytes,
                "pending_observed_work": pending,
                "collection_ended": True,
                "quiescence_asserted": False,
                "sha256": sha256_file(path),
            }
        )
    if seen_labels != EXPECTED_TRACE_LABELS:
        raise DiagnosticFailure(f"Trace label set mismatch: expected {sorted(EXPECTED_TRACE_LABELS)}, got {sorted(seen_labels)}")
    return {"outcome": "passed", "expected_labels": sorted(EXPECTED_TRACE_LABELS), "sessions": sessions}


def snapshot_files(root: Path, relative_paths: list[str]) -> dict[str, dict[str, str]]:
    snapshots: dict[str, dict[str, str]] = {}
    for relative in relative_paths:
        path = root / relative
        if not path.is_file():
            raise DiagnosticFailure(f"Patched source file is missing: {path}")
        snapshots[relative] = {"path": str(path), "sha256": sha256_file(path)}
    return snapshots


def snapshot_preimage(root: Path, relative_paths: list[str]) -> dict[str, dict[str, Any]]:
    snapshots: dict[str, dict[str, Any]] = {}
    for relative in relative_paths:
        path = root / relative
        snapshots[relative] = {
            "path": str(path),
            "existed": path.is_file(),
            "sha256": sha256_file(path) if path.is_file() else None,
        }
    return snapshots


def patch_numstat(patch: Path, base: Path) -> list[dict[str, str]]:
    result = subprocess.run(
        ["git", "-C", str(base), "apply", "--numstat", str(patch)],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if result.returncode != 0:
        raise DiagnosticFailure(f"Cannot record patch statistics for {patch}: {result.stderr.strip()}")
    rows: list[dict[str, str]] = []
    for line in result.stdout.splitlines():
        added, removed, path = line.split("\t", 2)
        rows.append({"added": added, "removed": removed, "path": path})
    return rows


def verify_snapshots(snapshots: dict[str, dict[str, str]]) -> dict[str, Any]:
    mismatches: list[str] = []
    for relative, snapshot in snapshots.items():
        path = Path(snapshot["path"])
        if not path.is_file() or sha256_file(path) != snapshot["sha256"]:
            mismatches.append(relative)
    return {"outcome": "passed" if not mismatches else "failed", "mismatches": mismatches}


def patch_files(repo: Path) -> tuple[Path, Path]:
    patch_dir = repo / PATCH_DIRECTORY
    neon_patch = patch_dir / "neon.patch"
    package_patch = patch_dir / "package.patch"
    for path in (neon_patch, package_patch):
        if not path.is_file():
            raise DiagnosticFailure(f"Required diagnostic patch is missing: {path}")
    return neon_patch, package_patch


def patch_paths(patch: Path, base: Path) -> list[str]:
    result = subprocess.run(
        ["git", "-C", str(base), "apply", "--numstat", str(patch)],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if result.returncode != 0:
        raise DiagnosticFailure(f"Cannot inspect patch {patch}: {result.stderr.strip()}")
    paths = [line.split("\t", 2)[2] for line in result.stdout.splitlines() if line.count("\t") >= 2]
    if not paths:
        raise DiagnosticFailure(f"Patch has no file changes: {patch}")
    return paths


def apply_patch(patch: Path, destination: Path, run: dict[str, Any], label: str) -> None:
    paths = patch_paths(patch, destination)
    if label == "apply_package_patch" and (
        len(paths) != len(ALLOWED_PACKAGE_PATCH_PATHS) or set(paths) != ALLOWED_PACKAGE_PATCH_PATHS
    ):
        raise DiagnosticFailure(
            "Package patch must touch exactly the manifest, edited regression test, and trace support file; "
            f"got {paths}"
        )
    if label == "apply_neon_patch" and any(not path.endswith(".swift") for path in paths):
        raise DiagnosticFailure(f"Neon patch may touch Swift sources only; got {paths}")
    run_command(
        ["git", "-C", str(destination), "apply", "--check", str(patch)],
        destination,
        Path(run["output_dir"]) / f"{label}-check.log",
        os.environ.copy(),
        run["commands"],
        f"{label}_check",
    )
    run_command(
        ["git", "-C", str(destination), "apply", str(patch)],
        destination,
        Path(run["output_dir"]) / f"{label}.log",
        os.environ.copy(),
        run["commands"],
        label,
    )


def write_run(run: dict[str, Any], output: Path) -> None:
    run["updated_at"] = utc_now()
    (output / "run.json").write_text(json.dumps(run, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def observe_tests(repo, package, command, env, output, run):
    path = repo / "MacDown2/scripts/neon-current-trace/observer.py"
    spec = importlib.util.spec_from_file_location("restore_trace_crash_capture", path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    previous_bytecode_setting = sys.dont_write_bytecode
    try:
        sys.dont_write_bytecode = True
        spec.loader.exec_module(module)
    finally:
        sys.dont_write_bytecode = previous_bytecode_setting
    log_path = output / "test.log"
    record = {"label": "swift_test", "argv": command, "cwd": str(package),
              "started_at": utc_now(), "log": str(log_path), "observer_sha256": sha256_file(path)}
    run["commands"].append(record)
    with log_path.open("w", encoding="utf-8") as log:
        log.write("$ " + shlex.join(command) + "\n")
        log.flush()
        observed = module.observed_command(
            command, package, lambda: module.locate_bundle(package),
            [Path.home() / "Library/Logs/DiagnosticReports", Path("/Library/Logs/DiagnosticReports")],
            env=env, stdout=log,
        )
        # Capture the known original status before file close, hashing or any
        # diagnostic bookkeeping can fail. main's return reads this directly.
        run["original_test_exit"] = observed["shell_exit_code"]
        record["exit_code"] = observed["shell_exit_code"]
        record["observed_command"] = observed
    record.update({"ended_at": utc_now(), "exit_code": observed["shell_exit_code"],
                   "outcome": "passed" if observed["shell_exit_code"] == 0 else "failed",
                   "log_sha256": sha256_file(log_path), "observed_command": observed})
    processes = observed["processes"]
    record["observer_integrity"] = (
        bool(processes) and not observed["observer_errors"] and "capture_error_type" not in observed
        and observed.get("coverage", {}).get("swift_testing_helper_observed", False)
        and all(p["final_state"] in {"absent", "pid_reused"} for p in processes)
        and all(not image["error"] for p in processes for image in p["executable_images"])
        and all(p["test_image"] is None or not p["test_image"]["error"] for p in processes)
    )
    return record


def main() -> int:
    script_path = Path(__file__).resolve()
    default_repo = script_path.parents[3]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workspace", required=True, type=Path, help="new directory for extracted package sources")
    parser.add_argument("--output", required=True, type=Path, help="new directory for logs and trace output")
    parser.add_argument("--repo", type=Path, default=default_repo, help="repository root (defaults from this script)")
    parser.add_argument("--filter", dest="test_filter", help="optional Swift test filter for local verification")
    args = parser.parse_args()

    repo = args.repo.expanduser().resolve()
    run: dict[str, Any] = {
        "schema_version": 1,
        "started_at": utc_now(),
        "status": "running",
        "repo": str(repo),
        "commands": [],
        "workspace": str(args.workspace.expanduser().resolve()),
        "output_dir": str(args.output.expanduser().resolve()),
        "test_filter": args.test_filter,
        "timeout_seconds_per_command": COMMAND_TIMEOUT_SECONDS,
        "environment_recorded": ["MOSTLYTEXT_RESTORE_TRACE_DIR"],
        "python": {"executable": sys.executable, "version": sys.version},
    }
    output: Path | None = None
    trace_dir: Path | None = None
    package_root: Path | None = None
    pins: list[dict[str, Any]] = []
    lock_hash: str | None = None
    neon_paths: set[str] = set()
    original_test_exit: int | None = None
    try:
        workspace_arg = args.workspace.expanduser().resolve()
        output_arg = args.output.expanduser().resolve()
        if workspace_arg == output_arg or is_within(workspace_arg, output_arg) or is_within(output_arg, workspace_arg):
            raise DiagnosticFailure("--workspace and --output must be distinct, non-nested directories")
        if is_within(workspace_arg, repo) or is_within(output_arg, repo):
            raise DiagnosticFailure("--workspace and --output must be outside the source repository")
        if workspace_arg.exists():
            raise DiagnosticFailure(f"--workspace must be a new directory; already exists: {workspace_arg}")
        if output_arg.exists():
            raise DiagnosticFailure(f"--output must be a new directory; already exists: {output_arg}")
        output = ensure_new_directory(output_arg, "--output")
        run["output_dir"] = str(output)
        workspace = ensure_new_directory(workspace_arg, "--workspace")
        run["workspace"] = str(workspace)

        if not (repo / ".git").exists():
            raise DiagnosticFailure(f"Repository root not found: {repo}")
        head = git(repo, "rev-parse", "HEAD")
        tree = git(repo, "rev-parse", "HEAD^{tree}")
        event_pr = github_pull_request_identity()
        run["source"] = {
            "head": head,
            "tree": tree,
            "merge_sha": head if event_pr is not None else None,
            "merge_tree": tree if event_pr is not None else None,
            "event_merge_sha": event_pr["event_merge_sha"] if event_pr is not None else None,
        }
        run["github_pull_request"] = event_pr
        validate_github_event(os.environ.get("GITHUB_EVENT_NAME"), os.environ.get("GITHUB_EVENT_PATH"), event_pr, head)
        before_attestation = source_attestation(repo)
        run["source_attestation_before"] = before_attestation
        if before_attestation.get("outcome") != "passed":
            raise DiagnosticFailure(f"Source preflight attestation failed: {before_attestation}")
        if before_attestation.get("head_sha") != head or before_attestation.get("tree_sha") != tree:
            raise DiagnosticFailure("Source HEAD/tree changed during initial attestation")
        lock_path = repo / "MacDown2/Packages/MacDownKit/Package.resolved"
        if not lock_path.is_file():
            raise DiagnosticFailure(f"Committed Package.resolved is missing: {lock_path}")
        pins = read_pins(lock_path)
        if len(pins) != EXPECTED_PIN_COUNT:
            raise DiagnosticFailure(f"Expected {EXPECTED_PIN_COUNT} locked dependency pins, found {len(pins)}")
        lock_hash = sha256_file(lock_path)
        if lock_hash != LOCK_SHA:
            raise DiagnosticFailure("Committed lock differs from the reviewed diagnostic baseline")
        run["lock"] = {"path": "MacDown2/Packages/MacDownKit/Package.resolved", "sha256": lock_hash, "pin_count": len(pins)}
        neon_patch, package_patch = patch_files(repo)
        run["patches"] = {
            "neon": {"path": str(neon_patch.relative_to(repo)), "sha256": sha256_file(neon_patch)},
            "package": {"path": str(package_patch.relative_to(repo)), "sha256": sha256_file(package_patch)},
        }

        run_command(["swift", "--version"], repo, output / "swift-version.log", os.environ.copy(), run["commands"], "swift_version")
        run_command(["xcodebuild", "-version"], repo, output / "xcode-version.log", os.environ.copy(), run["commands"], "xcode_version")

        package_dir = archive_packages(repo, workspace, output, run)
        package_patch_paths = patch_paths(package_patch, package_dir)
        if (
            len(package_patch_paths) != len(ALLOWED_PACKAGE_PATCH_PATHS)
            or set(package_patch_paths) != ALLOWED_PACKAGE_PATCH_PATHS
        ):
            raise DiagnosticFailure(
                "Package patch must touch exactly the six reviewed diagnostic files; "
                f"got {package_patch_paths}"
            )
        run["patch_manifest"] = {
            "package": {
                "paths": package_patch_paths,
                "numstat": patch_numstat(package_patch, package_dir),
                "preimage": snapshot_preimage(package_dir, package_patch_paths),
            }
        }
        apply_patch(package_patch, package_dir, run, "apply_package_patch")

        package_root = package_dir / "MacDownKit"
        package_snapshots = snapshot_files(package_dir, package_patch_paths)
        run["patched_source_snapshots"] = {"package": package_snapshots}
        env = os.environ.copy()
        trace_dir = output / "traces"
        trace_dir.mkdir()
        env["MOSTLYTEXT_RESTORE_TRACE_DIR"] = str(trace_dir)
        resolve = run_command(
            ["swift", "package", "resolve", "--force-resolved-versions"],
            package_root,
            output / "resolve.log",
            env,
            run["commands"],
            "resolve_locked_dependencies",
        )
        if sha256_file(package_root / "Package.resolved") != lock_hash:
            raise DiagnosticFailure("Package.resolved changed during locked dependency resolution")
        run["locked_checkouts"] = audit_checkouts(package_dir, pins)
        run["locked_checkouts_count"] = len(run["locked_checkouts"])

        neon_checkout = package_root / ".build" / "checkouts" / "Neon"
        if not neon_checkout.is_dir():
            raise DiagnosticFailure(f"Locked Neon checkout missing after resolve: {neon_checkout}")
        neon_paths_list = patch_paths(neon_patch, neon_checkout)
        run["patch_manifest"]["neon"] = {
            "paths": neon_paths_list,
            "numstat": patch_numstat(neon_patch, neon_checkout),
            "preimage": snapshot_preimage(neon_checkout, neon_paths_list),
        }
        apply_patch(neon_patch, neon_checkout, run, "apply_neon_patch")
        neon_paths = set(neon_paths_list)
        neon_snapshots = snapshot_files(neon_checkout, neon_paths_list)
        run["patched_source_snapshots"]["neon"] = neon_snapshots
        run["neon_patch_paths"] = sorted(neon_paths)
        run["patch_manifest"]["neon"]["post_patch_git_diff_stat"] = git(neon_checkout, "diff", "--stat")
        run["patch_manifest"]["neon"]["post_patch_status"] = git(
            neon_checkout, "status", "--porcelain", "--untracked-files=all"
        )

        build_record = run_command(
            ["swift", "build", "--build-tests", "--force-resolved-versions"],
            package_root,
            output / "build.log",
            env,
            run["commands"],
            "swift_build",
        )
        test_command = ["swift", "test", "--no-parallel", "--force-resolved-versions"]
        if args.test_filter:
            test_command.extend(["--filter", args.test_filter])
        test_bundle = locate_test_bundle(package_root)
        run["test_bundle"] = str(test_bundle)
        test_record = observe_tests(repo, package_root, test_command, env, output, run)
        original_test_exit = test_record["exit_code"]
        run["original_test_exit"] = original_test_exit
        try:
            run["trace_validation"] = validate_traces(trace_dir, {
                p["pid"] for p in test_record["observed_command"]["processes"]
                if p.get("argument_binding") in {"swift_testing_macho_flag", "swift_testing_bundle_flag"}
            })
        except Exception as error:
            run["trace_validation"] = {
                "outcome": "failed",
                "error": f"{type(error).__name__}: {error}",
            }
        if run["trace_validation"].get("outcome") != "passed":
            raise DiagnosticFailure(f"Trace validation failed: {run['trace_validation']}")
        run["status"] = "passed" if original_test_exit == 0 else "failed"
        run["completion"] = {"resolve": resolve["outcome"], "build": build_record["outcome"], "tests": test_record["outcome"]}
    except Exception as error:
        run["status"] = "failed"
        run["failure"] = f"{type(error).__name__}: {error}"
    finally:
        try:
            run["ended_at"] = utc_now()
            if output is not None:
                if trace_dir is not None and trace_dir.exists():
                    run["trace_files"] = sorted(
                        str(path.relative_to(output)) for path in trace_dir.rglob("*") if path.is_file()
                    )
                if package_root is not None and lock_hash is not None:
                    lock_after = package_root / "Package.resolved"
                    lock_matches = lock_after.is_file() and sha256_file(lock_after) == lock_hash
                    run["lock_after"] = {
                        "path": str(lock_after),
                        "sha256": sha256_file(lock_after) if lock_after.is_file() else None,
                        "matches_committed_lock": lock_matches,
                    }
                    if not lock_matches:
                        run["status"] = "failed"
                        run["failure"] = f"{run.get('failure', '')}; isolated Package.resolved changed after execution".strip("; ")
                    if pins:
                        try:
                            run["locked_checkouts_after"] = audit_post_diagnostic_checkouts(package_root.parent, pins, neon_paths)
                            run["locked_checkouts_after_count"] = len(run["locked_checkouts_after"])
                        except Exception as audit_error:
                            run["locked_checkouts_after"] = {
                                "outcome": "failed",
                                "error": f"{type(audit_error).__name__}: {audit_error}",
                            }
                            run["status"] = "failed"
                            run["failure"] = f"{run.get('failure', '')}; post-execution pin audit failed: {audit_error}".strip("; ")
                    snapshots = run.get("patched_source_snapshots", {})
                    run["patched_source_verification_after"] = {
                        key: verify_snapshots(value) for key, value in snapshots.items()
                    }
                    if any(value.get("outcome") != "passed" for value in run["patched_source_verification_after"].values()):
                        run["status"] = "failed"
                        run["failure"] = f"{run.get('failure', '')}; patched source bytes changed during execution".strip("; ")
                source = run.get("source", {})
                final_attestation = source_attestation(repo, source.get("head"), source.get("tree"))
                run["source_attestation_after"] = final_attestation
                if final_attestation.get("outcome") != "passed":
                    run["status"] = "failed"
                    final_failure = f"Final source attestation failed: {final_attestation}"
                    previous_failure = run.get("failure")
                    run["failure"] = f"{previous_failure}; {final_failure}" if previous_failure else final_failure
                test_records = [r for r in run["commands"] if r.get("label") == "swift_test"]
                run["diagnostic_integrity"] = "passed" if (
                    len(test_records) == 1 and test_records[0].get("observer_integrity") is True
                    and run.get("trace_validation", {}).get("outcome") == "passed"
                    and final_attestation.get("outcome") == "passed"
                    and run.get("source_attestation_before", {}).get("outcome") == "passed"
                    and run.get("lock_after", {}).get("matches_committed_lock") is True
                    and run.get("locked_checkouts_count") == EXPECTED_PIN_COUNT
                    and run.get("locked_checkouts_after_count") == EXPECTED_PIN_COUNT
                    and len(run.get("patched_source_verification_after", {})) == 2
                    and all(v.get("outcome") == "passed" for v in run["patched_source_verification_after"].values())
                ) else "unavailable"
                write_run(run, output)
        except Exception as error:
            run["diagnostic_integrity"] = "unavailable"
            run["finalization_error_type"] = type(error).__name__
            if output is not None:
                try:
                    write_run(run, output)
                except Exception:
                    pass  # Separate workflow integrity gate detects absent evidence.
    # The original test result wins; a separate workflow step gates evidence
    # completeness. Setup failure before tests has its own nonzero status.
    return run.get("original_test_exit", 2)


if __name__ == "__main__":
    raise SystemExit(main())
