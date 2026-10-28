"""One serial non-performance consolidation pass. Never retry a failed gate."""
from pathlib import Path
import datetime, hashlib, json, os, signal, subprocess, tarfile, time

repo = Path('/Users/jonathanlim/GitHub/macdown_2-integ')
raw = Path(__file__).resolve().parent
head = '400d475caaae130cdce1f6de4c6904027e700827'
base = '60f779fc0f7324cd5dd3b7b503030e9c22d7d44f'
package_skip = 'Performance|Benchmark|worstCaseScanStaysWithinAPerKeystrokeBudget|aHundredSecondaryCaretsStayWithinAReasonableDrawBudget'
app_skips = [
    'MacDown2Tests/WholeAppTabScalePerformanceTests/materializingTwentyTabsCompletesWithinBudget()',
    'MacDown2Tests/WholeAppTabScalePerformanceTests/switchingAcrossTwentyAlreadyOpenTabsIsCheapRelativeToFirstOpen()',
]

def git(*args):
    return subprocess.check_output(['git', *args], cwd=repo, text=True).strip()

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def utc():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()

def clean():
    assert git('rev-parse', 'HEAD') == head
    assert not git('status', '--porcelain')

record = {
    'head': head, 'base': base, 'tree': git('rev-parse', 'HEAD^{tree}'),
    'commands': [], 'package_skip_regex': package_skip, 'app_skips': app_skips,
    'performance_execution_authorized': False,
    'native_ui_execution': False, 'distribution_signing': False,
    'selection_rationale': [
        'Exclude named Performance/Benchmark tests and two separately named timing budgets.',
        'Retain node-count-only MarkdownTreeReuseTests despite inclusion in the historical performance command.',
        'Retain functional cleanup deadlines, boundedness and asynchronous timeout contracts.',
        'Retain the functional benchmark-window teardown test; exclude only its two timed benchmarks.',
        'Compile app and UI tests, then execute non-performance MacDown2Tests only, matching the CI target boundary.',
    ],
}

def save():
    (raw/'validation.json').write_text(json.dumps(record, indent=2)+'\n')

def run(name, argv, cwd=repo, expected=0, timeout=1800):
    clean()
    entry = {'name': name, 'argv': argv, 'cwd': str(cwd), 'started_utc': utc(),
             'expected_exit': expected, 'load_before': os.getloadavg()}
    started = time.monotonic()
    print('Starting '+name, flush=True)
    log = raw/(name+'.log')
    with log.open('xb') as output:
        proc = subprocess.Popen(argv, cwd=cwd, stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            code = proc.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, signal.SIGTERM)
            try:
                proc.wait(timeout=10)
            except subprocess.TimeoutExpired:
                os.killpg(proc.pid, signal.SIGKILL)
                proc.wait()
            code = 124
            entry['timeout'] = True
    entry.update(exit_code=code, ended_utc=utc(), seconds=time.monotonic()-started,
                 log_sha256=sha(log), load_after=os.getloadavg(),
                 head_after=git('rev-parse', 'HEAD'), status_after=git('status', '--porcelain'))
    record['commands'].append(entry)
    save()
    print(name+': exit '+str(code), flush=True)
    clean()
    if code == 124:
        raise RuntimeError('Timed out; stop heavy work and inspect retained process/evidence state.')
    return code == expected

clean()
archive = raw/('source-'+head+'.tar')
with archive.open('xb') as f:
    subprocess.run(['git', 'archive', head], cwd=repo, stdout=f, check=True)
source = raw/('source-'+head)
source.mkdir()
with tarfile.open(archive) as f:
    f.extractall(source, filter='data')
record['source_archive_sha256'] = sha(archive)
for name, args in [('overnight.diff', ['git', 'diff', '--binary', base, head]),
                   ('overnight-stat.txt', ['git', 'diff', '--stat', base, head])]:
    with (raw/name).open('xb') as f:
        subprocess.run(args, cwd=repo, stdout=f, check=True)
(raw/'FirstPartyWarnings.xcconfig').write_bytes(
    (repo/'compliance/evidence/prism-textual-1.29.0/FirstPartyWarnings.xcconfig').read_bytes())
for name, argv in [('os', ['sw_vers']), ('xcode', ['xcodebuild','-version']), ('swift', ['swift','--version'])]:
    run('environment-'+name, argv)
run('swiftformat', ['swiftformat','--lint','MacDown2'])
run('swiftlint', ['swiftlint','lint','--strict','MacDown2'])
run('source-compliance', ['python3','compliance/tools/compliance.py','check'], source)
run('release-preflight', ['python3','compliance/tools/compliance.py','check','--release'], source, expected=1)
run('compliance-tests', ['python3','-m','unittest','discover','-s','compliance/tests'], source)
run('legacy-map', ['python3','planning/downstream/tools/check_legacy_preference_map.py'])
run('legacy-map-tests', ['python3','-m','unittest','discover','-s','planning/downstream/tools','-p','test_legacy_preference_map.py'])
pkg = repo/'MacDown2/Packages/MacDownKit'
package_build = run('package-build', ['swift','build','--force-resolved-versions'], pkg)
if package_build:
    run('package-nonperformance-tests', ['swift','test','--no-parallel','--force-resolved-versions','--skip',package_skip], pkg)
    run('package-test-list', ['swift','test','--force-resolved-versions','list','--skip-build'], pkg)
else:
    record['package_tests_not_run'] = 'Required package build failed; no retry.'

generated = run('xcodegen', ['xcodegen','generate'], repo/'MacDown2')
if not generated:
    raise RuntimeError('Project generation failed; dependent app builds not run.')
assert run('pin-xcode', ['MacDown2/scripts/pin-xcode-package-versions.sh'])
(raw/'generated-project.pbxproj').write_bytes((repo/'MacDown2/MacDown2.xcodeproj/project.pbxproj').read_bytes())
common = ['xcodebuild','-derivedDataPath',str(raw/'DerivedData'),'-xcconfig',str(raw/'FirstPartyWarnings.xcconfig'),
          '-clonedSourcePackagesDirPath','/Users/jonathanlim/Library/Developer/Xcode/DerivedData/MacDown2-dzrmcfervtreklbefratupqpimsh/SourcePackages',
          '-project','MacDown2/MacDown2.xcodeproj','-destination','platform=macOS','-onlyUsePackageVersionsFromResolvedFile',
          'CODE_SIGNING_ALLOWED=NO','CODE_SIGNING_REQUIRED=NO']
debug_app = run('debug-app', common+['-scheme','MacDown2','-configuration','Debug','build'])
run('debug-cli', common+['-scheme','macdown2','-configuration','Debug','build'])
release_app = run('release-app', common+['-scheme','MacDown2','-configuration','Release','build'])
run('release-cli', common+['-scheme','macdown2','-configuration','Release','build'])
if debug_app:
    test_build = run('build-for-testing', common+['-scheme','MacDown2','-configuration','Debug','-enableCodeCoverage','NO','build-for-testing'])
    if test_build:
        test_args = common+['-scheme','MacDown2','-configuration','Debug','-enableCodeCoverage','NO','-parallel-testing-enabled','NO',
                           '-only-testing:MacDown2Tests', *['-skip-testing:'+x for x in app_skips]]
        record['app_test_argv'] = test_args+['-resultBundlePath',str(raw/'app-nonperformance-tests.xcresult'),'test-without-building']
        run('app-test-enumeration', test_args+['-enumerate-tests','-test-enumeration-style','flat','-test-enumeration-format','json',
                                             '-test-enumeration-output-path',str(raw/'app-test-enumeration.json'),'test-without-building'])
else:
    record['app_tests_not_run'] = 'Required Debug app build failed; no retry.'
if release_app:
    app = raw/'DerivedData/Build/Products/Release/MacDown2.app'
    record['release_artifact'] = str(app)
    run('artifact-compliance', ['python3','compliance/tools/compliance.py','check','--artifact',str(app)], source)
    run('artifact-release-preflight', ['python3','compliance/tools/compliance.py','check','--release','--artifact',str(app)], source, expected=1)
run('pins-match', ['MacDown2/scripts/pin-xcode-package-versions.sh','--check'])
run('unchanged-production-pins', ['git','diff','--exit-code',base,head,'--','MacDown2/Packages/MacDownKit/Package.resolved'])
record['phase_one_completed_utc'] = utc()
record['next'] = 'Inspect enumerated app selection before the one app-target test execution. No gate is retried.'
save()
print(record['next'], flush=True)
