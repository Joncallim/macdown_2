from pathlib import Path
import datetime,hashlib,json,os,signal,subprocess,time
raw=Path(__file__).resolve().parent
repo=Path('/Users/jonathanlim/GitHub/macdown_2-integ')
v=json.loads((raw/'validation.json').read_text())
def git(*a): return subprocess.check_output(['git',*a],cwd=repo,text=True).strip()
def utc(): return datetime.datetime.now(datetime.timezone.utc).isoformat()
assert git('rev-parse','HEAD')==v['head'] and not git('status','--porcelain')
selection=json.loads((raw/'app-selection-check.json').read_text())
assert len(selection['disabled'])==2 and selection['enabled_count']==415
assert not (raw/'app-nonperformance-tests.xcresult').exists()
entry={'name':'app-nonperformance-tests','argv':v['app_test_argv'],'cwd':str(repo),'started_utc':utc(),'load_before':os.getloadavg(),'head_before':git('rev-parse','HEAD'),'status_before':git('status','--porcelain'),'expected_exit':0}
start=time.monotonic();log=raw/'app-nonperformance-tests.log'
print('Starting the single app-target non-performance test execution',flush=True)
with log.open('xb') as out:
    proc=subprocess.Popen(entry['argv'],cwd=repo,stdout=out,stderr=subprocess.STDOUT,start_new_session=True)
    try: code=proc.wait(timeout=1800)
    except subprocess.TimeoutExpired:
        entry['timeout']=True;os.killpg(proc.pid,signal.SIGTERM)
        try:proc.wait(timeout=10)
        except subprocess.TimeoutExpired:os.killpg(proc.pid,signal.SIGKILL);proc.wait()
        code=124
entry.update(exit_code=code,ended_utc=utc(),seconds=time.monotonic()-start,log_sha256=hashlib.sha256(log.read_bytes()).hexdigest(),load_after=os.getloadavg(),head_after=git('rev-parse','HEAD'),status_after=git('status','--porcelain'))
v['commands'].append(entry);v['completed_utc']=utc();v['next']='Interpret all retained results without retrying any gate.'
(raw/'validation.json').write_text(json.dumps(v,indent=2)+'\n')
print('App-target test exit '+str(code),flush=True)
assert git('rev-parse','HEAD')==v['head'] and not git('status','--porcelain')
