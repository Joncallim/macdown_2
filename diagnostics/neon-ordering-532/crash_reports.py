"""Bounded crash collection with top-level PID AND process-name ownership."""
import base64
import json
import os
from pathlib import Path
import re
import stat
import time

CAP = 1024**2

def fixture_owners(text):
    owners = {}
    for pid, encoded in re.findall(r'NEON_FIXTURE pid=(\d+) fixture=[0-9A-Fa-f-]+ identity64=([A-Za-z0-9+/=]+)', text):
        try:
            name = base64.b64decode(encoded, validate=True).decode('utf-8')
        except (ValueError, UnicodeError):
            continue
        if name and '\n' not in name and '\x00' not in name:
            owners.setdefault(int(pid), set()).add(name)
    return owners

def crashed_process(text, suffix):
    if suffix == '.ips':
        decoder = json.JSONDecoder()
        cursor = 0
        documents = []
        try:
            while text[cursor:].strip():
                if len(documents) == 2:
                    return None
                cursor += len(text[cursor:]) - len(text[cursor:].lstrip())
                document, cursor = decoder.raw_decode(text, cursor)
                documents.append(document)
        except ValueError:
            return None
        # Apple .ips is usually one metadata object followed by one crash body.
        body = documents[-1] if documents else None
        if not isinstance(body, dict):
            return None
        pid, name = body.get('pid'), body.get('procName')
        if type(pid) is int and pid > 0 and isinstance(name, str) and name:
            return pid, name
    elif suffix == '.crash':
        headers = [re.fullmatch(r'Process:\s+(.+?)\s+\[(\d+)\]', line) for line in text.splitlines()[:40]]
        headers = [header for header in headers if header]
        if len(headers) == 1:
            return int(headers[0][2]), headers[0][1]
    return None

def read_regular(path, since):
    """O_NOFOLLOW plus fstat prevents a symlink/special-file replacement race."""
    try:
        info = path.lstat()
        if stat.S_ISLNK(info.st_mode):
            return None, 'symlink'
        if not stat.S_ISREG(info.st_mode):
            return None, 'nonregular'
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
        with os.fdopen(fd, 'rb') as handle:
            info = os.fstat(handle.fileno())
            if not stat.S_ISREG(info.st_mode):
                return None, 'nonregular'
            if info.st_mtime < since:
                return None, 'stale'
            if info.st_size > CAP:
                return None, 'oversized'
            data = handle.read(CAP + 1)
            return (None, 'oversized') if len(data) > CAP else (data, None)
    except OSError:
        return None, 'unreadable'

def collect(reports, output, since, owners, grace=3):
    result = {'owners': {str(pid): sorted(names) for pid, names in owners.items()},
              'copiedReports': 0, 'bytes': 0, 'scanned': 0, 'skipped': {}, 'exhaustion': []}
    if not reports.is_dir() or not owners:
        result['exhaustion'].append('no-directory' if not reports.is_dir() else 'no-correlated-fixture-identity')
        return result
    remaining = max(0, 8 * CAP - 64 * 1024 - sum(p.stat().st_size for p in output.glob('*.log')))
    deadline = time.monotonic() + grace
    seen = set()
    while time.monotonic() < deadline:
        with os.scandir(reports) as entries:
            for entry in entries:
                if time.monotonic() >= deadline or result['scanned'] >= 256:
                    result['exhaustion'].append('time' if time.monotonic() >= deadline else 'entry-cap')
                    return result
                path = Path(entry.path)
                if path in seen or path.suffix not in ('.ips', '.crash'):
                    continue
                seen.add(path)
                result['scanned'] += 1
                data, skip = read_regular(path, since)
                identity = crashed_process(data.decode('utf-8', errors='replace'), path.suffix) if data else None
                if skip is None and (identity is None or identity[1] not in owners.get(identity[0], set())):
                    skip = 'invalid-or-unowned-top-level-process'
                if skip:
                    result['skipped'][skip] = result['skipped'].get(skip, 0) + 1
                    continue
                if result['copiedReports'] >= 8 or result['bytes'] + len(data) > remaining:
                    result['exhaustion'].append('artifact-cap')
                    return result
                (output / f'crash-{result["copiedReports"]}{path.suffix}').write_bytes(data)
                result['bytes'] += len(data)
                result['copiedReports'] += 1
        time.sleep(min(0.2, max(0, deadline - time.monotonic())))
    result['exhaustion'].append('grace-expired')
    return result
