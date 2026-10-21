#!/usr/bin/env python3
"""Observe the ordinary SwiftPM test command and export only attributable crash stacks."""
from __future__ import annotations

import argparse
from collections import Counter
import ctypes
import errno
from dataclasses import dataclass, field
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import stat
import subprocess
import sys
import time
import uuid

BASE_PACKAGE_TREE = "04a5b4e873b71d1a866dfb01f7b52c835f767367"
LOCK_SHA = "58585f78359b7ae6998ee1a83caf4f8bcc029858d2b1ad576e8436b48956c1c2"
TEST_COMMAND = ["swift", "test", "--no-parallel", "--force-resolved-versions"]
PROCESS_NAMES = {"swift", "swift-test", "swiftpm-testing-helper", "xctest", "MacDownKitPackageTests"}
MAX_REPORT_BYTES = 8 * 1024 * 1024
MAX_TOTAL_BYTES = 64 * 1024 * 1024
MAX_CANDIDATES = 64
MAX_REPORTS = 8
MAX_FRAMES = 128
MAX_PROCESSES = 16
MAX_IMAGES_PER_PROCESS = 4
MAX_BINARY_BYTES = 2 * 1024 * 1024 * 1024
ARCHITECTURES = {"arm64", "arm64e", "x86_64"}
EXCEPTION_TYPES = {"EXC_BAD_ACCESS", "EXC_BAD_INSTRUCTION", "EXC_ARITHMETIC", "EXC_EMULATION",
                   "EXC_SOFTWARE", "EXC_BREAKPOINT", "EXC_SYSCALL", "EXC_MACH_SYSCALL",
                   "EXC_RPC_ALERT", "EXC_CRASH", "EXC_RESOURCE", "EXC_GUARD", "EXC_CORPSE_NOTIFY"}
SIGNALS = {"SIGABRT", "SIGBUS", "SIGFPE", "SIGILL", "SIGKILL", "SIGQUIT", "SIGSEGV", "SIGSYS", "SIGTERM", "SIGTRAP"}
TERMINATION_NAMESPACES = {"SIGNAL", "DYLD", "CODESIGNING", "LIBSYSTEM", "OBJC", "WATCHDOG", "JETSAM", "RUNNINGBOARD"}


def file_sha(path: Path, deadline: float) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        total = 0
        while block := source.read(1024 * 1024):
            total += len(block)
            if total > MAX_BINARY_BYTES or time.monotonic() >= deadline:
                raise Rejected("binary_hash_bound")
            digest.update(block)
    return digest.hexdigest()


class Rejected(ValueError):
    """A fixed, public rejection reason; never initialized from report content."""


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def utc() -> str:
    return datetime.now(timezone.utc).isoformat()


def run_text(argv: list[str], cwd: Path | None = None, timeout=10) -> str:
    return subprocess.check_output(argv, cwd=cwd, text=True, stderr=subprocess.DEVNULL, timeout=timeout).strip()


def file_stamp(path: Path) -> tuple[int, int, int, int]:
    info = path.stat()
    if not stat.S_ISREG(info.st_mode):
        raise Rejected("not_regular")
    return info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns


class BSDInfo(ctypes.Structure):
    # Darwin SDK sys/proc_info.h, PROC_PIDTBSDINFO. Do not export account fields.
    _fields_ = [(name, ctypes.c_uint32) for name in (
        "flags", "status", "xstatus", "pid", "ppid", "uid", "gid", "ruid", "rgid", "svuid", "svgid", "reserved"
    )] + [("comm", ctypes.c_char * 16), ("name", ctypes.c_char * 32)] + [
        (name, ctypes.c_uint32) for name in ("nfiles", "pgid", "pjobc", "tdev", "tpgid")
    ] + [("nice", ctypes.c_int32), ("start_sec", ctypes.c_uint64), ("start_usec", ctypes.c_uint64)]


@dataclass(frozen=True)
class Process:
    pid: int
    ppid: int
    birth_us: int
    executable: str


class DarwinProcesses:
    def __init__(self):
        self.lib = ctypes.CDLL("/usr/lib/libproc.dylib", use_errno=True)
        self.lib.proc_pidinfo.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_uint64, ctypes.c_void_p, ctypes.c_int]
        self.lib.proc_pidinfo.restype = ctypes.c_int
        self.lib.proc_pidpath.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_uint32]
        self.lib.proc_pidpath.restype = ctypes.c_int

    def identity(self, pid: int) -> Process | None:
        info = BSDInfo()
        size = ctypes.sizeof(info)
        if self.lib.proc_pidinfo(pid, 3, 0, ctypes.byref(info), size) != size or info.pid != pid:
            return None
        buf = ctypes.create_string_buffer(4096)
        if self.lib.proc_pidpath(pid, buf, len(buf)) <= 0:
            return None
        after = BSDInfo()
        if self.lib.proc_pidinfo(pid, 3, 0, ctypes.byref(after), size) != size:
            return None
        if (info.pid, info.ppid, info.start_sec, info.start_usec) != (after.pid, after.ppid, after.start_sec, after.start_usec):
            return None
        return Process(pid, info.ppid, info.start_sec * 1_000_000 + info.start_usec, os.fsdecode(buf.value))

    def command(self, pid: int) -> str:
        return run_text(["ps", "-ww", "-p", str(pid), "-o", "command="])

    def commands(self) -> dict[int, tuple[int, str]]:
        # Read only ancestry globally; argv is queried only for a candidate helper.
        result = {}
        for line in run_text(["ps", "-axo", "pid=,ppid="]).splitlines():
            fields = line.split()
            if len(fields) == 2 and all(field.isdigit() for field in fields):
                result[int(fields[0])] = (int(fields[1]), "")
        return result

    def final_state(self, process: Process) -> str:
        ctypes.set_errno(0)
        current = self.identity(process.pid)
        if current is not None:
            return "alive_same_birth" if current.birth_us == process.birth_us else "pid_reused"
        return "absent" if ctypes.get_errno() == errno.ESRCH else "unavailable"


@dataclass
class Image:
    path: Path
    observed_stamp: tuple[int, int, int, int]
    uuids: set[str] = field(default_factory=set)
    digest: str | None = None
    error: str | None = None

    def seal(self, deadline):
        try:
            remaining = deadline - time.monotonic()
            if remaining <= 0 or self.observed_stamp[2] > MAX_BINARY_BYTES:
                raise Rejected("binary_seal_bound")
            if file_stamp(self.path) != self.observed_stamp:
                raise Rejected("changed_image")
            output = run_text(["xcrun", "dwarfdump", "--uuid", str(self.path)], timeout=min(10, remaining))
            self.uuids = {str(uuid.UUID(value)) for value in re.findall(r"UUID: ([0-9A-Fa-f-]{36})", output)}
            if not self.uuids:
                raise Rejected("missing_uuid")
            self.digest = file_sha(self.path, deadline)
            if file_stamp(self.path) != self.observed_stamp:
                raise Rejected("changed_image")
        except Exception as error:
            self.error = type(error).__name__
            self.uuids.clear()
            self.digest = None


@dataclass
class Owned:
    process: Process
    role: str
    admitted_parent: tuple[int, int] | None
    images: dict[str, Image] = field(default_factory=dict)
    bundle_image: Image | None = None
    last_seen_us: int = 0
    argument_binding: str | None = None

    def observe(self, current: Process):
        if (current.pid, current.birth_us) != (self.process.pid, self.process.birth_us):
            raise Rejected("birth_changed")
        if current.executable not in self.images:
            if len(self.images) >= MAX_IMAGES_PER_PROCESS:
                raise Rejected("process_image_bound")
            path = Path(current.executable)
            self.images[current.executable] = Image(path, file_stamp(path))
        self.last_seen_us = time.time_ns() // 1000


def test_argument_binding(executable: str, arguments: list[str], bundle: Path) -> str | None:
    test_image = bundle / "Contents/MacOS/MacDownKitPackageTests"
    if executable == str(test_image):
        return "direct_test_image"
    if Path(executable).name == "swiftpm-testing-helper":
        # SwiftPM gives this helper the Mach-O path inside the XCTest bundle.
        # Bind the exact flag/value pair; an unrelated positional path is not proof.
        if arguments and arguments[-1] == "--test-bundle-path":
            return None
        values = [arg.partition("=")[2] for arg in arguments if arg.startswith("--test-bundle-path=")]
        values.extend(arguments[index + 1] for index, arg in enumerate(arguments[:-1]) if arg == "--test-bundle-path")
        if len(values) != 1:
            return None
        if values[0] == str(test_image):
            return "swift_testing_macho_flag"
        if values[0] == str(bundle):
            return "swift_testing_bundle_flag"
        return None
    return "xctest_bundle_argument" if Path(executable).name == "xctest" and str(bundle) in arguments else None


def coverage(processes: list[dict]) -> dict:
    helpers = [process for process in processes if process["role"] == "test_helper"]
    xctest = any(process.get("argument_binding") == "xctest_bundle_argument" for process in helpers)
    swift_testing = any(process.get("argument_binding") in {"swift_testing_macho_flag", "swift_testing_bundle_flag"}
                        and any(image["name"] == "swiftpm-testing-helper" for image in process["executable_images"])
                        for process in helpers)
    return {"xctest_observed": xctest, "swift_testing_helper_observed": swift_testing}


class Observer:
    def __init__(self, process_api, bundle_provider):
        self.api = process_api
        self.bundle_provider = bundle_provider
        self.owned: dict[int, Owned] = {}
        self.errors: Counter = Counter()

    def poll(self, child):
        try:
            root = self.api.identity(child.pid)
            if root is None:
                return
            if child.poll() is not None:
                return
            prior = self.owned.get(child.pid)
            if prior is None:
                if root.ppid != os.getpid():
                    self.errors["root_parent_mismatch"] += 1
                    return
                prior = self.owned[child.pid] = Owned(root, "launcher", None)
            if root.birth_us != prior.process.birth_us or root.ppid != os.getpid():
                self.errors["root_identity_changed"] += 1
                return
            prior.observe(root)
            commands = self.api.commands()
            # Admit only known test executables with the exact freshly built bundle
            # argument and a currently verified owned parent. Never persist argv.
            for pid, (ppid, command) in commands.items():
                if pid == child.pid:
                    continue
                known = self.owned.get(pid)
                if known is None and ppid not in self.owned:
                    continue
                current = self.api.identity(pid)
                if current is None:
                    continue
                if known is not None:
                    if current.birth_us == known.process.birth_us:
                        known.observe(current)  # Original ownership survives reparenting.
                    continue
                if Path(current.executable).name not in PROCESS_NAMES - {"swift", "swift-test"}:
                    continue
                parent = self.api.identity(current.ppid)
                owned_parent = self.owned.get(current.ppid)
                if parent is None or owned_parent is None or parent.birth_us != owned_parent.process.birth_us:
                    continue
                bundle = self.bundle_provider()
                if bundle is None:
                    continue
                # Bind argv to the same process birth/path, rather than trusting a
                # possibly stale row from the earlier system-wide PID listing.
                command = self.api.command(pid)
                if self.api.identity(pid) != current:
                    self.errors["admission_identity_changed"] += 1
                    continue
                arguments = shlex.split(command)
                binding = test_argument_binding(current.executable, arguments, bundle)
                if binding is None:
                    continue
                if len(self.owned) >= MAX_PROCESSES:
                    self.errors["process_bound"] += 1
                    continue
                test_image = bundle / "Contents/MacOS/MacDownKitPackageTests"
                known = Owned(current, "test_helper", (parent.pid, parent.birth_us),
                              bundle_image=Image(test_image, file_stamp(test_image)), argument_binding=binding)
                known.observe(current)
                self.owned[pid] = known
        except Exception as error:
            self.errors[type(error).__name__] += 1

    def seal(self, deadline):
        for owned in self.owned.values():
            for image in list(owned.images.values()) + ([owned.bundle_image] if owned.bundle_image else []):
                image.seal(deadline)


def timestamp(value) -> tuple[int, int]:
    if not isinstance(value, str) or len(value) > 48:
        raise Rejected("missing_timestamp")
    matched = re.fullmatch(r"(\d{4}-\d\d-\d\d[ T]\d\d:\d\d:\d\d)(?:\.(\d{1,6}))? ?(Z|[+-]\d\d:?\d\d)", value)
    if not matched:
        raise Rejected("invalid_timestamp")
    fraction = matched[2] or ""
    parsed = datetime.fromisoformat(matched[1] + ("." + fraction if fraction else "") + matched[3].replace("Z", "+00:00"))
    micros = int(parsed.timestamp()) * 1_000_000 + parsed.microsecond
    return micros, 10 ** (6 - len(fraction))


def decode_report(data: bytes) -> tuple[dict, dict]:
    decoder = json.JSONDecoder()
    text = data.decode("utf-8")
    first, end = decoder.raw_decode(text.lstrip())
    rest = text.lstrip()[end:].strip()
    body = decoder.decode(rest) if rest else first
    if not isinstance(first, dict) or not isinstance(body, dict):
        raise Rejected("invalid_report_shape")
    return (first if rest else {}), body


def normalized_uuid(value) -> str | None:
    try:
        return str(uuid.UUID(value)) if isinstance(value, str) else None
    except ValueError:
        return None


def path_binding(reported, observed: Path) -> str | None:
    if not isinstance(reported, str):
        return None
    if reported == str(observed):
        return "exact"
    # Apple privacy-redacts home paths in .ips reports. This single observed
    # shape is only a path qualifier; acceptance still requires the sealed UUID,
    # observed PID/precise birth and capture interval, with no ambiguous image.
    if observed.is_relative_to(Path.home()) and reported == "/Users/USER/*/" + observed.name:
        return "apple_home_redaction"
    return None


def attributable(body: dict, owned: Owned, start_us: int, end_us: int) -> tuple[str, Image]:
    process = owned.process
    if type(body.get("pid")) is not int or body["pid"] != process.pid:
        raise Rejected("pid_mismatch")
    launch_us, quantum = timestamp(body.get("procLaunch"))
    # Report serialization may round one unit of its printed precision. Require
    # fractional precision at least milliseconds; never accept a broad seconds window.
    if quantum > 1000 or abs(launch_us - process.birth_us) > quantum:
        raise Rejected("birth_mismatch_or_precision_unavailable")
    captured_us, capture_quantum = timestamp(body.get("captureTime"))
    if not max(start_us, process.birth_us) - capture_quantum <= captured_us <= end_us + capture_quantum:
        raise Rejected("capture_outside_command")
    images = body.get("usedImages")
    if not isinstance(images, list) or len(images) > 2048:
        raise Rejected("invalid_images")
    matches = [image for image in owned.images.values() if not image.error and image.uuids
               and path_binding(body.get("procPath"), image.path)
               and any(isinstance(item, dict) and item.get("path") == body.get("procPath")
                       and normalized_uuid(item.get("uuid")) in image.uuids for item in images)]
    if len(matches) != 1:
        raise Rejected("process_image_unavailable_or_ambiguous")
    image = matches[0]
    bundle = owned.bundle_image
    if bundle is not None:
        entries = [item for item in images if isinstance(item, dict)
                   and (path_binding(item.get("path"), bundle.path)
                        or normalized_uuid(item.get("uuid")) in bundle.uuids)]
        if not entries:
            return "owned_helper_before_test_image_loaded", image
        if bundle.error or not all(path_binding(item.get("path"), bundle.path)
                                   and normalized_uuid(item.get("uuid")) in bundle.uuids for item in entries):
            raise Rejected("test_image_uuid_mismatch_or_unavailable")
        return "test_process", image
    return "owned_launcher_before_verified_test_binding", image


def safe_name(value, limit=1024) -> str | None:
    if not isinstance(value, str) or len(value) > limit or any(ord(c) < 32 for c in value):
        return None
    # Only used for text emitted from a verified owned binary, never report text.
    if "/" in value or "\\" in value:
        return None
    return value


def export_stack(body: dict, category: str, report_hash: str) -> dict:
    threads, images = body.get("threads"), body.get("usedImages")
    fault = body.get("faultingThread")
    if not isinstance(threads, list) or len(threads) > 4096 or type(fault) is not int or not 0 <= fault < len(threads):
        raise Rejected("missing_faulting_thread")
    frames = threads[fault].get("frames") if isinstance(threads[fault], dict) else None
    if not isinstance(frames, list) or not frames:
        raise Rejected("missing_frames")
    exported, referenced = [], set()
    for frame in frames[:MAX_FRAMES]:
        if not isinstance(frame, dict):
            raise Rejected("invalid_frame")
        index, offset = frame.get("imageIndex"), frame.get("imageOffset")
        if type(index) is not int or type(offset) is not int or not 0 <= index < len(images) or not 0 <= offset < 2**64:
            raise Rejected("invalid_frame_address")
        row = {"image_index": index, "image_offset": offset}
        exported.append(row)
        referenced.add(index)
    used = []
    for index in sorted(referenced):
        item = images[index]
        if not isinstance(item, dict):
            raise Rejected("invalid_image")
        row = {"index": index, "uuid": normalized_uuid(item.get("uuid"))}
        for key in ("base", "size"):
            if type(item.get(key)) is int and item[key] >= 0:
                row[key] = item[key]
        if item.get("arch") in ARCHITECTURES:
            row["arch"] = item["arch"]
        used.append(row)
    result = {"category": category, "raw_report_sha256": report_hash, "pid": body["pid"],
              "process_path_sha256": sha(os.fsencode(body["procPath"])),
              "proc_launch": body["procLaunch"], "capture_time": body["captureTime"],
              "faulting_thread": fault, "frames": exported, "referenced_images": used,
              "frames_omitted": max(0, len(frames) - MAX_FRAMES),
              "symbolication": "unsymbolicated"}
    for section, allowed in (("exception", {"type": EXCEPTION_TYPES, "signal": SIGNALS}),
                             ("termination", {"namespace": TERMINATION_NAMESPACES})):
        values = body.get(section)
        if isinstance(values, dict):
            selected = {key: values[key] for key, choices in allowed.items()
                        if isinstance(values.get(key), str) and values[key] in choices}
            if type(values.get("code")) is int and 0 <= values["code"] < 2**64:
                selected["code"] = values["code"]
            if selected:
                result[section] = selected
    return result


def symbolicate(exported: dict, body: dict, owned: Owned, deadline: float):
    """Use only UUID-verified owned binaries; never open an arbitrary report path."""
    images = list(owned.images.values()) + ([owned.bundle_image] if owned.bundle_image else [])
    attempts = []
    for image in images:
        if image.error or not image.uuids:
            continue
        for index, entry in enumerate(body["usedImages"]):
            if (not isinstance(entry, dict) or not path_binding(entry.get("path"), image.path)
                    or normalized_uuid(entry.get("uuid")) not in image.uuids):
                continue
            base, arch = entry.get("base"), entry.get("arch")
            frames = [f for f in exported["frames"] if f["image_index"] == index]
            if not frames or type(base) is not int or arch not in ARCHITECTURES:
                continue
            attempt = {"image_index": index, "binary_sha256": image.digest, "status": "unavailable"}
            try:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise Rejected("symbolication_deadline")
                if file_stamp(image.path) != image.observed_stamp:
                    raise Rejected("changed_image")
                addresses = [hex(base + f["image_offset"]) for f in frames]
                lines = run_text(["xcrun", "atos", "-o", str(image.path), "-arch", arch,
                                  "-l", hex(base), *addresses], timeout=min(10, remaining)).splitlines()
                if file_stamp(image.path) != image.observed_stamp or len(lines) != len(frames):
                    raise Rejected("symbolication_identity_or_shape")
                for frame, line in zip(frames, lines):
                    # Atos source locations can carry absolute paths: keep only the
                    # symbol before its image/source suffix, never the raw line.
                    symbol = safe_name(line.split(" (in ", 1)[0])
                    if symbol and not re.fullmatch(r"0x[0-9a-fA-F]+", symbol):
                        frame["verified_binary_symbol"] = symbol
                attempt["status"] = "completed"
            except Exception as error:
                attempt["error_type"] = type(error).__name__
            attempts.append(attempt)
    exported["symbolication_attempts"] = attempts
    resolved = sum("verified_binary_symbol" in frame for frame in exported["frames"])
    exported["symbolication"] = ("complete" if resolved == len(exported["frames"]) else
                                 "partial" if resolved else "unsymbolicated")


def candidate_stamps(directories: list[Path], names: set[str], since_us=0, errors=None) -> dict[Path, tuple]:
    results = {}
    for directory in directories:
        try:
            with os.scandir(directory) as entries:
                for entry in entries:
                    if not entry.name.endswith(".ips") or not any(entry.name.startswith(name + "-") for name in names):
                        continue
                    info = entry.stat(follow_symlinks=False)
                    if info.st_mtime_ns // 1000 < since_us:
                        continue
                    results[Path(entry.path)] = (info.st_dev, info.st_ino, info.st_size, info.st_mtime_ns)
                    if len(results) > MAX_CANDIDATES:
                        raise Rejected("candidate_bound_reached")
        except FileNotFoundError:
            continue
        except OSError as error:
            if errors is not None:
                errors["directory_" + type(error).__name__] += 1
    return results


def read_regular(path: Path, byte_limit=MAX_REPORT_BYTES) -> bytes:
    descriptor = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    try:
        info = os.fstat(descriptor)
        if not stat.S_ISREG(info.st_mode) or not 0 < info.st_size <= min(MAX_REPORT_BYTES, byte_limit):
            raise Rejected("report_size_or_type")
        data = os.read(descriptor, MAX_REPORT_BYTES + 1)
        after = os.fstat(descriptor)
        if len(data) != info.st_size or (info.st_ino, info.st_size, info.st_mtime_ns) != (after.st_ino, after.st_size, after.st_mtime_ns):
            raise Rejected("report_incomplete")
        return data
    finally:
        os.close(descriptor)


def collect_reports(directories, before, observer, start_us, end_us, wait_seconds):
    reports, seen, counters = [], {}, Counter()
    total_bytes = 0
    names = {Path(image.path).name for owned in observer.owned.values() for image in owned.images.values()}
    deadline = time.monotonic() + max(0.05, wait_seconds)
    while True:
        try:
            candidates = candidate_stamps(directories, names, start_us, counters)
            for path, stamp in candidates.items():
                if time.monotonic() >= deadline:
                    counters["capture_deadline"] += 1
                    break
                if before.get(path) == stamp or seen.get(path) == stamp or stamp[3] // 1000 < start_us:
                    continue
                if len(seen) >= MAX_CANDIDATES or total_bytes >= MAX_TOTAL_BYTES or len(reports) >= MAX_REPORTS:
                    counters["capture_bound_reached"] += 1
                    break
                seen[path] = stamp
                try:
                    data = read_regular(path, MAX_TOTAL_BYTES - total_bytes)
                    total_bytes += len(data)
                    _, body = decode_report(data)
                    owned = observer.owned.get(body.get("pid"))
                    if owned is None:
                        counters["unowned_pid"] += 1
                        continue
                    category, process_image = attributable(body, owned, start_us, end_us)
                    exported = export_stack(body, category, sha(data))
                    exported["executable_path_binding"] = path_binding(body["procPath"], process_image.path)
                    symbolicate(exported, body, owned, deadline)
                    if not any(r["raw_report_sha256"] == exported["raw_report_sha256"] for r in reports):
                        reports.append(exported)
                except Exception as error:
                    # Never export parser snippets, rejected names, paths, or raw fields.
                    counters[error.args[0] if isinstance(error, Rejected) else type(error).__name__] += 1
        except Exception as error:
            counters[error.args[0] if isinstance(error, Rejected) else type(error).__name__] += 1
        if time.monotonic() >= deadline or counters["capture_bound_reached"] or counters["candidate_bound_reached"]:
            break
        time.sleep(min(0.5, max(0, deadline - time.monotonic())))
    return {"outcome": "matched" if reports else "no_matching_report", "reports": reports,
            "counters": dict(counters), "bytes_examined": total_bytes}


def image_export(image: Image) -> dict:
    return {"name": image.path.name, "sha256": image.digest, "uuids": sorted(image.uuids),
            "path_sha256": sha(os.fsencode(image.path)), "size": image.observed_stamp[2], "error": image.error}


def processes_export(observer):
    results = []
    for owned in observer.owned.values():
        state = observer.api.final_state(owned.process)
        results.append({"pid": owned.process.pid, "birth_us": owned.process.birth_us,
                        "admitted_parent": owned.admitted_parent, "role": owned.role,
                        "argument_binding": owned.argument_binding,
                        "last_seen_us": owned.last_seen_us,
                        "executable_images": [image_export(i) for i in owned.images.values()],
                        "test_image": image_export(owned.bundle_image) if owned.bundle_image else None,
                        "final_state": state})
    return results


def observed_command(command, cwd, bundle_provider, directories, report_wait=30):
    # No pipes, environment overrides, session/group changes, debugger, handlers,
    # signals, product timeout, retries, or sleeps inside the tested process.
    setup_errors = Counter()
    try:
        before = candidate_stamps(directories, PROCESS_NAMES | {Path(command[0]).name}, errors=setup_errors)
    except Exception as error:
        before = {}
        setup_errors[type(error).__name__] += 1
    try:
        observer = Observer(DarwinProcesses(), bundle_provider)
    except Exception as error:
        observer = None
        setup_errors[type(error).__name__] += 1
    started_us = time.time_ns() // 1000
    child = subprocess.Popen(command, cwd=cwd)
    while child.poll() is None:
        if observer is not None:
            observer.poll(child)
        time.sleep(0.1)
    code = child.wait()
    ended_us = time.time_ns() // 1000
    result = {"argv": command, "start_us": started_us, "end_us": ended_us,
              "return_code": code, "signal": -code if code < 0 else None,
              "shell_exit_code": code if code >= 0 else 128 - code,
              "processes": [], "observer_errors": dict(setup_errors),
              "capture": {"outcome": "unavailable", "reports": []}}
    # Capture failures must not lose or replace the original command status.
    try:
        if observer is not None:
            deadline = time.monotonic() + report_wait
            observer.seal(deadline)  # Shared post-exit budget; never delays the test.
            remaining = deadline - time.monotonic()
            result["capture"] = (collect_reports(directories, before, observer, started_us, ended_us, remaining)
                                 if code != 0 and remaining > 0 else
                                 {"outcome": "post_exit_deadline" if code != 0 else "not_needed", "reports": []})
            result["processes"] = processes_export(observer)
            result["coverage"] = coverage(result["processes"])
            result["observer_errors"].update(observer.errors)
    except Exception as error:
        result["capture_error_type"] = type(error).__name__
    return result


def attest(repo: Path):
    def git(*args):
        return run_text(["git", *args], repo)
    package = repo / "MacDown2/Packages/MacDownKit"
    lock = package / "Package.resolved"
    checks = {"head": git("rev-parse", "HEAD"), "tree": git("rev-parse", "HEAD^{tree}"),
              "package_tree": git("rev-parse", "HEAD:MacDown2/Packages"),
              "source_clean": not git("status", "--porcelain", "--untracked-files=all"), "lock_sha256": sha(lock.read_bytes())}
    pins = json.loads(lock.read_text())["pins"]
    checkouts = {path.name.lower(): path for path in (package / ".build/checkouts").iterdir() if path.is_dir()}
    checks["dependencies"] = []
    for pin in pins:
        path = checkouts[pin["identity"]]
        actual = run_text(["git", "rev-parse", "HEAD"], path)
        clean = not run_text(["git", "status", "--porcelain", "--untracked-files=all"], path)
        checks["dependencies"].append({"identity": pin["identity"], "expected": pin["state"]["revision"], "actual": actual, "clean": clean})
    checks["passed"] = (checks["package_tree"] == BASE_PACKAGE_TREE and checks["source_clean"]
                        and checks["lock_sha256"] == LOCK_SHA and len(pins) == 22
                        and all(d["actual"] == d["expected"] and d["clean"] for d in checks["dependencies"]))
    return checks


def locate_bundle(package):
    paths = {p.resolve() for p in (package / ".build").glob("*/debug/MacDownKitPackageTests.xctest")
             if (p / "Contents/MacOS/MacDownKitPackageTests").is_file()}
    if len(paths) != 1:
        return None
    bundle = paths.pop()
    return bundle if bundle.is_relative_to((package / ".build").resolve()) else None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    repo, output = args.repo.resolve(), args.output.resolve()
    if output.is_relative_to(repo):
        raise Rejected("output_must_be_outside_repository")
    output.mkdir(parents=True, exist_ok=False)
    record = {"schema": 1, "started_at": utc(), "diagnostic_integrity": "unavailable"}
    code = 2
    try:
        record["source_before"] = attest(repo)
        if not record["source_before"]["passed"]:
            raise Rejected("source_attestation_failed")
        event_path = os.environ.get("GITHUB_EVENT_PATH")
        if event_path:
            event = json.loads(Path(event_path).read_text())
            pr = event.get("pull_request", {})
            record["github"] = {"head": pr.get("head", {}).get("sha"), "base": pr.get("base", {}).get("sha"),
                                "run_id": os.environ.get("GITHUB_RUN_ID"), "attempt": os.environ.get("GITHUB_RUN_ATTEMPT")}
        package = repo / "MacDown2/Packages/MacDownKit"
        record["command"] = observed_command(TEST_COMMAND, package, lambda: locate_bundle(package),
                                               [Path.home() / "Library/Logs/DiagnosticReports", Path("/Library/Logs/DiagnosticReports")])
        code = record["command"]["shell_exit_code"]
        record["source_after"] = attest(repo)
        valid = record["source_after"]["passed"] and record["source_after"]["head"] == record["source_before"]["head"]
        processes = record["command"]["processes"]
        valid = valid and bool(processes) and not record["command"]["observer_errors"] and "capture_error_type" not in record["command"]
        valid = valid and record["command"].get("coverage", {}).get("swift_testing_helper_observed", False)
        valid = valid and all(p["final_state"] in {"absent", "pid_reused"} for p in processes)
        valid = valid and all(not image["error"] for p in processes for image in p["executable_images"])
        valid = valid and all(p["test_image"] is None or not p["test_image"]["error"] for p in processes)
        record["diagnostic_integrity"] = "passed" if valid else "unavailable"
    except Exception as error:
        record["diagnostic_error_type"] = type(error).__name__
    finally:
        # Artifact I/O can fail too; once known, the command status wins.
        # No buffered stdout write: shutdown flush errors can replace exit with 120.
        try:
            record["ended_at"] = utc()
            (output / "run.json").write_text(json.dumps(record, indent=2, sort_keys=True) + "\n")
        except Exception:
            pass  # The separate workflow integrity step detects missing evidence.
    return code


if __name__ == "__main__":
    sys.exit(main())
