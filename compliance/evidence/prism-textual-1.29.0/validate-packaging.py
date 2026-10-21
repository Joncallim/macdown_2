"""Finite validation of the committed licence-packaging candidate; no signing."""
from pathlib import Path
import datetime,hashlib,json,subprocess,tarfile,time,sys
repo=Path('/Users/jonathanlim/GitHub/macdown_2-integ')
raw=Path(__file__).resolve().parent
head=sys.argv[1]
base='09e223bffd63c9b080592f566cfe6e2bbde4d8a7'
def git(*args):return subprocess.check_output(['git',*args],cwd=repo,text=True).strip()
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def utc():return datetime.datetime.now(datetime.timezone.utc).isoformat()
def clean():
 assert git('rev-parse','HEAD')==head
 assert not git('status','--porcelain')
clean()
archive=raw/('source-'+head+'.tar')
with archive.open('xb') as f:subprocess.run(['git','archive',head],cwd=repo,stdout=f,check=True)
source=raw/('source-'+head);source.mkdir()
with tarfile.open(archive) as f:f.extractall(source,filter='data')
record={'head':head,'base':base,'tree':git('rev-parse','HEAD^{tree}'),'source_archive_sha256':sha(archive),'commands':[],'performance_suites_run':False,'native_ui_run':False,'signing_performed':False}
def run(name,args,cwd=repo,expected=0,timeout=1800):
 clean();start=time.monotonic()
 entry={'name':name,'argv':args,'cwd':str(cwd),'started_utc':utc(),'expected_exit':expected}
 print('Starting '+name,flush=True)
 log=raw/(name+'.log')
 with log.open('xb') as f:r=subprocess.run(args,cwd=cwd,stdout=f,stderr=subprocess.STDOUT,timeout=timeout)
 entry.update(exit_code=r.returncode,seconds=time.monotonic()-start,ended_utc=utc(),log_sha256=sha(log),head_after=git('rev-parse','HEAD'),status_after=git('status','--porcelain'))
 record['commands'].append(entry);(raw/'validation.json').write_text(json.dumps(record,indent=2)+'\n')
 print(name+': exit '+str(r.returncode),flush=True);clean()
 assert r.returncode==expected,'Unexpected result retained; no automatic retry: '+name
 return log.read_text()
run('swiftformat',['swiftformat','--lint','MacDown2'])
run('swiftlint',['swiftlint','lint','--strict','MacDown2'])
run('source-compliance',['python3','compliance/tools/compliance.py','check'],source)
release=run('release-preflight',['python3','compliance/tools/compliance.py','check','--release'],source,expected=1)
failures=[s for s in release.splitlines() if s.startswith('FAIL:')]
prior=json.loads((repo/'compliance/evidence/swiftui-math-fonts-2026-10-18/validation.json').read_text())['remaining_release_findings']
assert failures==prior and len(failures)==7
record['remaining_release_findings']=failures
run('compliance-regressions',['python3','-m','unittest','discover','-s','compliance/tests'],source)
for name,path in [('notices','compliance/generated/THIRD_PARTY_NOTICES.md'),('sbom','compliance/generated/sbom.cdx.json')]:
 before=sha(source/path);run('regenerate-'+name,['python3','compliance/tools/compliance.py',name],source);assert sha(source/path)==before
run('xcodegen',['xcodegen','generate'],repo/'MacDown2')
run('pin-xcode',['MacDown2/scripts/pin-xcode-package-versions.sh'])
project=repo/'MacDown2/MacDown2.xcodeproj/project.pbxproj'
(raw/'generated-project.pbxproj').write_bytes(project.read_bytes())
assert 'LICENSE in Resources' in project.read_text() and 'THIRD_PARTY_NOTICES.md in Resources' in project.read_text()
dd=raw/'DerivedData'
run('release-app',['xcodebuild','-derivedDataPath',str(dd),'-xcconfig',str(raw/'FirstPartyWarnings.xcconfig'),'-clonedSourcePackagesDirPath','/Users/jonathanlim/Library/Developer/Xcode/DerivedData/MacDown2-dzrmcfervtreklbefratupqpimsh/SourcePackages','-project','MacDown2/MacDown2.xcodeproj','-scheme','MacDown2','-configuration','Release','-destination','platform=macOS','-onlyUsePackageVersionsFromResolvedFile','CODE_SIGNING_ALLOWED=NO','CODE_SIGNING_REQUIRED=NO','build'])
app=dd/'Build/Products/Release/MacDown2.app'
record['artifact_path']=str(app)
record['main_app_resources']={}
for file,source_file in [('LICENSE','LICENSE'),('THIRD_PARTY_NOTICES.md','compliance/generated/THIRD_PARTY_NOTICES.md')]:
 p=app/'Contents/Resources'/file;assert p.is_file() and p.read_bytes()==(source/source_file).read_bytes()
 record['main_app_resources'][file]={'path':str(p),'bytes':p.stat().st_size,'sha256':sha(p)}
run('artifact-compliance',['python3','compliance/tools/compliance.py','check','--artifact',str(app)],source)
ar=run('artifact-release-preflight',['python3','compliance/tools/compliance.py','check','--release','--artifact',str(app)],source,expected=1)
assert [s for s in ar.splitlines() if s.startswith('FAIL:')]==failures
record['artifact_files']={str(p.relative_to(app)):{'bytes':p.stat().st_size,'sha256':sha(p)} for p in sorted(app.rglob('*')) if p.is_file() and not p.is_symlink()}
inv=json.loads((source/'compliance/inventory.json').read_text())
for component_id in ['prismjs-textual','swiftui-math-fonts']:
 component=next(c for c in inv['components'] if c['id']==component_id)
 for resource in component['runtime_resources']:
  assert any(v['sha256']==resource['sha256'] for v in record['artifact_files'].values()),resource['name']
run('pins-match',['MacDown2/scripts/pin-xcode-package-versions.sh','--check'])
run('unchanged-pins-and-runtime-source',['git','diff','--exit-code',base,head,'--','MacDown2/Packages','MacDown2/MacDown2','MacDown2/MacDown2CLI','compliance/tools','compliance/tests'])
run('diff-check',['git','diff','--check',base,head])
record['completed_utc']=utc();record['result']='Exact unsigned Release artifact passes ordinary compliance with both required main-app licence resources and audited Prism bytes. Release preflight still fails on seven unchanged findings.'
(raw/'validation.json').write_text(json.dumps(record,indent=2)+'\n')
print(record['result'],flush=True)
