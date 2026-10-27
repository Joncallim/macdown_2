"""Fail closed on SwiftPM workspace redirection, lost patches or empty tracing."""
import hashlib
import json
from pathlib import Path
import subprocess

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def canonical(url):
    return url.removesuffix('.git').lower()

def assert_workspace(scratch, pins):
    state = json.loads((scratch / 'workspace-state.json').read_text())['object']['dependencies']
    remote = {item['packageRef']['identity']: item for item in state
              if item['packageRef']['kind'] == 'remoteSourceControl'}
    if set(remote) != {pin['identity'] for pin in pins}:
        raise ValueError('Effective workspace remote graph differs from all committed pins')
    result = []
    for pin in pins:
        item = remote[pin['identity']]
        path = (scratch / 'checkouts' / item['subpath']).resolve()
        if not path.is_relative_to((scratch / 'checkouts').resolve()):
            raise ValueError('Checkout escaped scratch root')
        revision = item['state'].get('checkoutState', {}).get('revision')
        if revision != pin['state']['revision'] or canonical(item['packageRef']['location']) != canonical(pin['location']):
            raise ValueError('Effective revision/location mismatch: ' + pin['identity'])
        actual = subprocess.run(['git', 'rev-parse', 'HEAD'], cwd=path, check=True,
                                capture_output=True, text=True, timeout=10).stdout.strip()
        if actual != revision:
            raise ValueError('Checkout HEAD disagrees with workspace')
        result.append({'identity': pin['identity'], 'revision': revision, 'path': str(path)})
    return result

def patched_files(directory, patch):
    paths = [line[6:] for line in patch.read_text().splitlines() if line.startswith('+++ b/')]
    result = {}
    for relative in paths:
        path = (directory / relative).resolve()
        if not path.is_relative_to(directory.resolve()):
            raise ValueError('Patch path escapes expected root')
        result[str(path)] = digest(path)
    return result

def verify_files(files):
    for path, expected in files.items():
        if digest(Path(path)) != expected:
            raise ValueError('Patched file changed during compilation: ' + path)

def assert_build_inputs(scratch, neon, repo, files, modules=None):
    candidates = list(scratch.glob('*/debug/description.json'))
    if len(candidates) != 1 or candidates[0].stat().st_size > 4 * 1024**2:
        raise ValueError('Missing, ambiguous or oversized SwiftPM build description')
    description = json.loads(candidates[0].read_text())
    selected = {}
    for module in modules or ('RangeState', 'TreeSitterClient', 'Neon', 'Highlighting', 'HighlightingTests'):
        commands = [c for c in description['swiftCommands'].values() if c['moduleName'] == module]
        if len(commands) != 1:
            raise ValueError('Missing or ambiguous compiled module: ' + module)
        command = commands[0]
        sources = {str(Path(source).resolve()) for source in command['sources']}
        inputs = {str(Path(item['name']).resolve()) for item in command['inputs'] if item['kind'] == 'file'}
        if module in ('RangeState', 'TreeSitterClient', 'Neon'):
            expected_root = (neon / 'Sources' / module).resolve()
            if not sources or any(not Path(source).is_relative_to(expected_root) for source in sources):
                raise ValueError('Neon module uses an unpatched/alternate source directory: ' + module)
        needed = {path for path in files if '/Sources/' + module + '/' in path}
        if module.endswith('Tests'):
            needed = {path for path in files if '/Tests/' + module + '/' in path}
        if not needed <= sources or not needed <= inputs:
            raise ValueError('Patched files missing from actual compiler inputs: ' + module)
        if not command['objects'] or any(not Path(path).is_file() for path in command['objects']):
            raise ValueError('Expected compiled objects are missing: ' + module)
        selected[module] = sorted(needed)
    return {'descriptionSHA256': digest(candidates[0]), 'patchedCompilerInputs': selected}

def correlated_events(text):
    fixtures = {line.split('fixture=', 1)[1].split()[0] for line in text.splitlines() if line.startswith('NEON_FIXTURE ')}
    events = []
    for line in text.splitlines():
        if line.startswith('NEON_ORDER '):
            events.append(dict(token.split('=', 1) for token in line.split()[2:] if '=' in token))
    correlated = []
    for fixture in fixtures:
        for enqueue in [e for e in events if e.get('fixture') == fixture and e.get('phase') == 'enqueue']:
            callbacks = [e for e in events if e.get('phase') == 'callback' and e.get('op') == enqueue.get('op')
                         and e.get('client') == enqueue.get('client') and e.get('processor') == enqueue.get('processor')
                         and e.get('fixture') == fixture]
            requests = [e for e in events if e.get('phase') == 'request' and e.get('parent') == enqueue.get('op')
                        and e.get('client') == enqueue.get('client') and e.get('fixture') == fixture
                        and e.get('processor') != enqueue.get('processor') and e.get('op') != enqueue.get('op')]
            compares = [e for e in events if e.get('phase') == 'compare' and e.get('op') == enqueue.get('op')
                        and e.get('processor') == enqueue.get('processor') and e.get('client') == enqueue.get('client')
                        and e.get('expected') == enqueue.get('parent') and e.get('fixture') == fixture]
            executions = [e for e in events if e.get('phase') == 'execute' and any(
                e.get('op') == request.get('op') and e.get('processor') == request.get('processor')
                and e.get('client') == request.get('client') and e.get('fixture') == fixture for request in requests)]
            if callbacks and requests and compares and executions:
                correlated.append({'fixture': fixture, 'client': enqueue['client'], 'mutation': enqueue['op']})
                break
    if len(fixtures) != 2 or len(correlated) != 2:
        raise ValueError('Need two fixture identities with correlated NEON_ORDER mutation/worker/compare events')
    return correlated
