#!/usr/bin/env python3
"""Reproduce the restore-trace diagnostic against an isolated locked package copy."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import signal
import shlex
import subprocess
import sys
import tarfile
import time
from datetime import datetime, timezone
from typing import Any


BASELINE_COMMIT = "ad79f2773f2cbaf8bb78bdb796b1d11b411be79b"
COMMAND_TIMEOUT_SECONDS = 30 * 60
TERMINATE_GRACE_SECONDS = 10
HELPER_POLL_SECONDS = 0.25
EXPECTED_PIN_COUNT = 22
MAX_TRACE_EVENTS = 32768
MAX_TRACE_PAYLOAD_BYTES = 16 * 1024 * 1024
EXPECTED_TRACE_LABELS = {"restore-idle-false", "restore-idle-true"}
PATCH_DIRECTORY = Path("planning/diagnostics/restore-trace")
ALLOWED_PACKAGE_PATCH_PATHS = {
    "MacDownKit/Package.swift",
    "MacDownKit/Tests/HighlightingTests/HighlightingSizeFallbackTests.swift",
    "MacDownKit/Tests/HighlightingTests/RestoreHostedTraceSupport.swift",
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


def run_command(
    argv: list[str],
    cwd: Path,
    log_path: Path,
    env: dict[str, str],
    records: list[dict[str, Any]],
    label: str,
    helper_test_bundle: Path | None = None,
) -> dict[str, Any]:
    """Run a bounded command and signal only a verified, still-live owned process group."""
    record: dict[str, Any] = {
        "label": label,
        "argv": argv,
        "cwd": str(cwd),
        "started_at": utc_now(),
        "timeout_seconds": COMMAND_TIMEOUT_SECONDS,
        "log": str(log_path),
        "outcome": "running",
        "pid": None,
    }
    if helper_test_bundle is not None:
        record["helper_test_bundle"] = str(helper_test_bundle.resolve())
    records.append(record)
    process: subprocess.Popen[str] | None = None
    owner_identity: dict[str, str] | None = None
    owned_helpers: dict[int, dict[str, str]] = {}
    helper_errors: list[dict[str, str]] = []
    try:
        with log_path.open("w", encoding="utf-8", errors="replace") as log:
            log.write(f"$ (cd {cwd} && {' '.join(argv)})\n")
            log.flush()
            process = subprocess.Popen(
                argv,
                cwd=cwd,
                env=env,
                stdout=log,
                stderr=subprocess.STDOUT,
                text=True,
                start_new_session=True,
            )
            record["pid"] = process.pid
            owner_identity = snapshot_process_identity(process.pid)
            if helper_test_bundle is not None and owner_identity is None:
                raise DiagnosticFailure("Could not snapshot the owned swift test process identity")
            try:
                deadline = time.monotonic() + COMMAND_TIMEOUT_SECONDS
                while process.poll() is None and time.monotonic() < deadline:
                    if helper_test_bundle is not None:
                        inspect_owned_helpers(process.pid, owner_identity, helper_test_bundle, owned_helpers, helper_errors)
                    try:
                        process.wait(timeout=HELPER_POLL_SECONDS if helper_test_bundle else 1)
                    except subprocess.TimeoutExpired:
                        continue
                if process.poll() is None:
                    raise subprocess.TimeoutExpired(argv, COMMAND_TIMEOUT_SECONDS)
                exit_code = process.returncode
                record["exit_code"] = exit_code
                record["outcome"] = "passed" if exit_code == 0 else "failed"
            except subprocess.TimeoutExpired:
                record["outcome"] = "timed_out"
                record["timed_out"] = True
                if helper_test_bundle is not None:
                    record["owned_helper_cleanup"] = terminate_verified_helpers(owned_helpers)
                record["process_group_cleanup"] = terminate_owned_process_group(process)
                record["exit_code"] = process.poll()
                log.write(f"\n[runner] timed out after {COMMAND_TIMEOUT_SECONDS} seconds\n")
                log.flush()
    except Exception as error:  # retain a record even if launch itself fails
        record["outcome"] = "launch_failed"
        record["error"] = f"{type(error).__name__}: {error}"
        raise
    finally:
        record["ended_at"] = utc_now()
        if helper_test_bundle is not None:
            if process is not None and process.poll() is None:
                inspect_owned_helpers(process.pid, owner_identity, helper_test_bundle, owned_helpers, helper_errors)
            if owned_helpers:
                helper_cleanup = record.setdefault("owned_helper_cleanup", {})
                helper_cleanup["post_command_cleanup"] = terminate_verified_helpers(owned_helpers)
            helper_cleanup = record.setdefault("owned_helper_cleanup", {})
            helper_cleanup["tracked"] = [
                {"pid": pid, **identity} for pid, identity in sorted(owned_helpers.items())
            ]
            helper_cleanup["scan_errors"] = helper_errors
            helper_cleanup["remaining_verified_helpers"] = verify_helpers_gone(owned_helpers, helper_errors)
            helper_cleanup["outcome"] = (
                "passed"
                if not helper_cleanup["remaining_verified_helpers"] and not helper_errors
                else "failed"
            )
            if not owned_helpers:
                helper_cleanup["observation"] = "no_matching_owned_helper_observed"
            if helper_cleanup["remaining_verified_helpers"] or helper_errors:
                record["outcome"] = "cleanup_incomplete"
        if process is not None:
            if process.poll() is None:
                if "process_group_cleanup" not in record:
                    record["process_group_cleanup"] = terminate_owned_process_group(process)
            else:
                record.setdefault(
                    "process_group_cleanup",
                    {
                        "outcome": "parent_already_exited_no_signal",
                        "detail": "Skipped group signal to avoid a potentially reused process-group ID",
                    },
                )
        if log_path.exists():
            record["log_sha256"] = sha256_file(log_path)

    if record["outcome"] != "passed":
        raise DiagnosticFailure(
            f"{label} {record['outcome']} (exit={record.get('exit_code')}); see {log_path}"
        )
    return record


def process_rows() -> list[tuple[int, int, str, str]]:
    result = subprocess.run(
        ["ps", "-axo", "pid=,ppid=,lstart=,command="],
        check=False,
        timeout=5,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if result.returncode != 0:
        raise DiagnosticFailure(f"Cannot inspect process identities: {result.stderr.strip()}")
    rows: list[tuple[int, int, str, str]] = []
    for line in result.stdout.splitlines():
        parts = line.strip().split(None, 7)
        if len(parts) != 8:
            continue
        try:
            rows.append((int(parts[0]), int(parts[1]), " ".join(parts[2:7]), parts[7]))
        except ValueError:
            continue
    return rows


def contains_exact_bundle_argument(command: str, bundle: Path) -> bool:
    expected = str(bundle.resolve())
    try:
        arguments = shlex.split(command)
    except ValueError:
        return False
    for argument in arguments:
        normalized = os.path.normpath(argument)
        if normalized == expected or normalized.startswith(expected + os.sep):
            return True
    return False


def snapshot_process_identity(pid: int) -> dict[str, str] | None:
    for row_pid, _, started, command in process_rows():
        if row_pid == pid:
            return {"started": started, "command_sha256": hashlib.sha256(command.encode()).hexdigest()}
    return None


def inspect_owned_helpers(
    owner_pid: int,
    owner_identity: dict[str, str] | None,
    bundle: Path,
    owned: dict[int, dict[str, str]],
    errors: list[dict[str, str]],
) -> None:
    try:
        rows = process_rows()
    except Exception as error:
        errors.append({"kind": "process_scan_failed", "detail": f"{type(error).__name__}: {error}"})
        return
    owner = next((row for row in rows if row[0] == owner_pid), None)
    if owner_identity is None or owner is None:
        return
    if (
        owner[2] != owner_identity["started"]
        or hashlib.sha256(owner[3].encode()).hexdigest() != owner_identity["command_sha256"]
    ):
        errors.append({"kind": "owned_command_identity_mismatch", "detail": f"pid={owner_pid}; helper scan refused"})
        return
    for pid, parent, started, command in rows:
        if parent != owner_pid or "swiftpm-testing-helper" not in command:
            continue
        if not contains_exact_bundle_argument(command, bundle):
            continue
        owned.setdefault(
            pid,
            {
                "parent_pid": str(parent),
                "started": started,
                "command_sha256": hashlib.sha256(command.encode()).hexdigest(),
                "bundle": str(bundle.resolve()),
            },
        )


def helper_identity(pid: int) -> tuple[int, str, str, str] | None:
    for row_pid, parent, started, command in process_rows():
        if row_pid == pid:
            return parent, started, hashlib.sha256(command.encode()).hexdigest(), command
    return None


def signal_verified_helper(pid: int, identity: dict[str, str], sig: signal.Signals) -> dict[str, str]:
    try:
        current = helper_identity(pid)
    except Exception as error:
        return {"pid": str(pid), "outcome": "identity_check_failed", "detail": f"{type(error).__name__}: {error}"}
    if current is None:
        return {"pid": str(pid), "outcome": "already_exited"}
    parent, started, command_hash, command = current
    if (
        command_hash != identity["command_sha256"]
        or started != identity["started"]
        or "swiftpm-testing-helper" not in command
        or not contains_exact_bundle_argument(command, Path(identity["bundle"]))
    ):
        return {"pid": str(pid), "outcome": "identity_mismatch_refused", "observed_parent_pid": str(parent)}
    try:
        os.kill(pid, sig)
        return {"pid": str(pid), "outcome": f"{sig.name.lower()}_sent_verified_identity"}
    except ProcessLookupError:
        return {"pid": str(pid), "outcome": "already_exited"}
    except OSError as error:
        return {"pid": str(pid), "outcome": "signal_failed", "detail": str(error)}


def terminate_verified_helpers(owned: dict[int, dict[str, str]]) -> dict[str, Any]:
    events = [signal_verified_helper(pid, identity, signal.SIGTERM) for pid, identity in owned.items()]
    deadline = time.monotonic() + TERMINATE_GRACE_SECONDS
    while time.monotonic() < deadline:
        try:
            if all(helper_identity(pid) is None for pid in owned):
                break
            time.sleep(0.1)
        except Exception:
            break
    for pid, identity in owned.items():
        try:
            current = helper_identity(pid)
            if current is not None:
                events.append(signal_verified_helper(pid, identity, signal.SIGKILL))
        except Exception as error:
            events.append(
                {"pid": str(pid), "outcome": "identity_check_failed", "detail": f"{type(error).__name__}: {error}"}
            )
    return {"events": events}


def verify_helpers_gone(owned: dict[int, dict[str, str]], errors: list[dict[str, str]]) -> list[int]:
    remaining: list[int] = []
    for pid, identity in owned.items():
        try:
            current = helper_identity(pid)
        except Exception as error:
            errors.append({"kind": "final_identity_check_failed", "detail": f"pid={pid}: {error}"})
            remaining.append(pid)
            continue
        if current is None:
            continue
        _, started, command_hash, command = current
        if started == identity["started"] and command_hash == identity["command_sha256"] and contains_exact_bundle_argument(
            command, Path(identity["bundle"])
        ):
            remaining.append(pid)
        else:
            errors.append({"kind": "final_identity_mismatch_refused", "detail": f"pid={pid}"})
    return remaining


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
        baseline_check = subprocess.run(
            ["git", "-C", str(repo), "cat-file", "-e", f"{BASELINE_COMMIT}^{{commit}}"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
        baseline_diff = subprocess.run(
            ["git", "-C", str(repo), "diff", "--quiet", BASELINE_COMMIT, "HEAD", "--", "MacDown2/Packages"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
        baseline_available = baseline_check.returncode == 0
        package_diff_empty = baseline_available and baseline_diff.returncode == 0
        matches_expected = (expected_head is None or head == expected_head) and (
            expected_tree is None or tree == expected_tree
        )
        clean = not source_status and not package_status
        outcome = baseline_available and package_diff_empty and matches_expected and clean
        return {
            "outcome": "passed" if outcome else "failed",
            "head_sha": head,
            "tree_sha": tree,
            "expected_head_matches": expected_head is None or head == expected_head,
            "expected_tree_matches": expected_tree is None or tree == expected_tree,
            "baseline_commit_available": baseline_available,
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


def validate_traces(trace_dir: Path) -> dict[str, Any]:
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
        session_id = trace.get("session")
        events = trace.get("events")
        dropped = trace.get("droppedEvents")
        payload_bytes = trace.get("payloadBytes")
        if trace.get("schema") != 1:
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
        seen_labels.add(label)
        seen_sessions.add(session_id)
        pending = trace.get("pendingObservedWork")
        if not isinstance(pending, list) or not all(isinstance(item, str) for item in pending):
            raise DiagnosticFailure(f"Malformed pendingObservedWork field in {path.name}")
        sessions.append(
            {
                "file": path.name,
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
        if os.environ.get("GITHUB_EVENT_PATH") and event_pr is None:
            raise DiagnosticFailure("GITHUB_EVENT_PATH did not contain a pull request identity")
        if event_pr is not None and any(not event_pr[field] for field in ("head_sha", "base_sha", "head_ref", "base_ref")):
            raise DiagnosticFailure("GitHub pull request event is missing head/base SHA or ref")
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
                "Package patch must touch exactly the manifest, edited regression test, and trace support file; "
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
        test_error: str | None = None
        try:
            run_command(
                test_command,
                package_root,
                output / "test.log",
                env,
                run["commands"],
                "swift_test",
                helper_test_bundle=test_bundle,
            )
        except Exception as error:
            test_error = str(error)
        try:
            run["trace_validation"] = validate_traces(trace_dir)
        except Exception as error:
            run["trace_validation"] = {
                "outcome": "failed",
                "error": f"{type(error).__name__}: {error}",
            }
        if test_error is not None:
            raise DiagnosticFailure(f"{test_error}; trace validation={run['trace_validation']}")
        if run["trace_validation"].get("outcome") != "passed":
            raise DiagnosticFailure(f"Trace validation failed: {run['trace_validation']}")
        run["status"] = "passed"
        run["completion"] = {"resolve": resolve["outcome"], "build": build_record["outcome"], "tests": "passed"}
    except Exception as error:
        run["status"] = "failed"
        run["failure"] = f"{type(error).__name__}: {error}"
        print(run["failure"], file=sys.stderr)
    finally:
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
            write_run(run, output)
            print(f"restore-trace evidence: {output / 'run.json'}")
    return 0 if run["status"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
