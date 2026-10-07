"""Four bounded synthetic OFF contracts, real owned temporary Popen waits/files.
Synthetic codec modules exercise the exact read-only subprocess call shape;
no Game Saved, live root, native Game, network or production codec is accessed.
"""
import ast, contextlib, hashlib, importlib.util, json, os, subprocess, sys, tempfile, time, types
from pathlib import Path

D=Path(__file__).resolve().parents[1]
DEV,USER,TOOLS='PalCraft-Dev','PalCraft-User','PalCraft-Dev/player-tools'
class Reject(Exception):
    pass
def fail(code,message,*args):
    raise Reject(code)
def read(path,default=None):
    return json.loads(Path(path).read_text()) if Path(path).exists() else default
def atomic(path,value):
    path=Path(path);path.parent.mkdir(parents=True,exist_ok=True);path.write_text(json.dumps(value))
def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def owned(root,name):
    p=Path(root)/name
    assert p.resolve().is_relative_to(Path(root).resolve()) and not p.is_symlink()
    return p
def identity(pid):
    try:os.kill(pid,0)
    except (ProcessLookupError,TypeError):return None
    return {'pid':pid,'identity':'synthetic-owned:'+str(pid)}
core=types.ModuleType('installer.core')
for key,value in dict(DEV=DEV,USER=USER,TOOLS=TOOLS,PlayerError=Reject,atomic_json=atomic,digest=digest,fail=fail,
    get_state=lambda r:read(Path(r)/'.palcraft/state.json'),marker=lambda r:read(Path(r)/'.palcraft/marker.json'),
    owned_path=owned,read_json=read,operation_lock=lambda r:contextlib.nullcontext(),ensure_no_session=lambda r:None).items():setattr(core,key,value)
sys.modules['installer']=types.ModuleType('installer');sys.modules['installer.core']=core
sys.modules['launcher']=types.ModuleType('launcher')
runtime=types.ModuleType('launcher.runtime');runtime.process_identity=identity
runtime.process_matches=lambda v:identity(v.get('pid'))is not None;runtime._port_free=lambda p:True
sys.modules['launcher.runtime']=runtime
spec=importlib.util.spec_from_file_location('launcher.journal_lifecycle',D/'source/launcher/journal_lifecycle.py')
J=importlib.util.module_from_spec(spec);sys.modules[spec.name]=J;spec.loader.exec_module(J)
token='a'*32;uid='00000000-0000-0000-0000-000000000001';world='d'*32
def fixture(root,level_uid=uid):
    children=[]
    for code in [3,0]:
        p=subprocess.Popen([sys.executable,'-c','raise SystemExit('+str(code)+')'])
        record={'pid':p.pid,'identity':'synthetic-owned:'+str(p.pid),'created_by_this_supervisor':True}
        assert p.wait()==code;children.append(record)
    client,supervisor=children
    started=time.time()-5
    native={'server_session_id':'standalone:synthetic','process_epoch':str(client['pid'])+':12345',
        'pid':client['pid'],'world_id':world,'pal_uid':uid,'save_boot_id':'synthetic-process-binding'}
    actor=dict(client,role='client');exits={'client':dict(actor,actual_wait_completed=True,exit_code=3,normal_stop_request=None)}
    profile={'platform':'crossover','pal_entry_mode':'singleplayer','standalone':{'save_account_directory':'synthetic-account'},
        'connection':{'transport':'local','server_session_id':native['server_session_id'],'identity':{'world_id':world,'pal_uid':uid}}}
    atomic(root/'.palcraft/state.json',{'profile':profile});atomic(root/'.palcraft/marker.json',{'id':'synthetic-root'})
    scope={'root':str(root),'root_id':'synthetic-root','token':token,'native_scope':native,'started_unix':started,
        'actors':{'client':actor},'active_events_path':str(root/J.EVENTS)}
    session={'phase':'failed','code':'CLIENT_EXIT','token':token,'supervisor':supervisor,'journal_lifecycle':{'actor_exits':exits}}
    atomic(root/'.palcraft/session.json',session);atomic(root/J.LIFECYCLE/'current.json',{'token':token})
    atomic(J._scope_path(root,token,'scope.json'),scope)
    atomic(J._scope_path(root,token,'incomplete-stop.json'),{'token':token,'code':'JOURNAL_WITNESS_PENDING','actor_exits':exits,'normal_save_witness':None})
    report=root/USER/'Saved/Crashes/synthetic/CrashContext.runtime-xml';report.parent.mkdir(parents=True)
    report.write_text('<root><ProcessId>'+str(client['pid'])+'</ProcessId><CrashType>Crash</CrashType></root>')
    os.utime(report,(time.time()-1,time.time()-1))
    atomic(root/'.palcraft/control'/f'{token}.host.json',{'primary_pid':client['pid'],'primary_alive':False,'job_active_processes':0,'phase':'failed','exit_code':3})
    atomic(root/DEV/'bridge/exchange/escrow-client-process-binding.json',{'pid':client['pid'],'process_created_filetime':'12345',
        'boot_id':native['save_boot_id'],'world_directory':world,'pal_uid':uid})
    atomic(root/'.palcraft/standalone/owned-loaded-save-permission.json',{'process_epoch':native['process_epoch']})
    level=root/USER/'Saved/SaveGames/synthetic-account'/world/'Level.sav';atomic(level,{'uid':level_uid})
    player=level.parent/'Players'/f'{uid.replace("-","").upper()}.sav';atomic(player,{'player':uid})
    atomic(root/'.palcraft/standalone/scope.json',{'installed_level_path_host':str(level),'world_directory':world,'pal_uid':uid})
    events=root/J.EVENTS;events.parent.mkdir(parents=True,exist_ok=True);events.write_text('synthetic ordinary old event\n')
    money=root/DEV/'bridge/exchange/escrow-synthetic.r000001.json';atomic(money,{'status':'needs_recovery','not_a_real_transaction':True})
    vendor=root/DEV/'mcp/vendor/palworld_save_tools';vendor.mkdir(parents=True)
    (vendor/'__init__.py').write_text('')
    (vendor/'palsav.py').write_text('def decompress_sav_to_gvas(data):return data,None\n')
    (vendor/'paltypes.py').write_text('PALWORLD_TYPE_HINTS={}\n')
    (vendor/'gvas.py').write_text('import json\nclass GvasFile:\n @staticmethod\n def read(data,*args,**kwargs):\n  value=json.loads(data)\n  uid=value.get("uid","")\n  return type("Fixture",(),{"properties":{"worldSaveData":{"value":{"CharacterSaveParameterMap":{"value":[{"key":{"PlayerUId":{"value":uid}}}]}}}}})()\n')
    return scope,session,profile,level,player,money,events
def reject(fn,code):
    try:fn()
    except Reject as e:assert str(e)==code,str(e)
    else:raise AssertionError('accepted '+code)
with tempfile.TemporaryDirectory(prefix='palcraft-synthetic-unsaved-')as folder:
    for case in range(4):
        root=Path(folder)/str(case);root.mkdir();scope,session,profile,level,player,money,events=fixture(root)
        snapshots={p:digest(p)for p in [level,player,money,root/'.palcraft/state.json',root/'.palcraft/session.json']}
        if case==0:
            dry=J.finalize_crash_off(root,True);assert dry['dry_run']and not J._scope_path(root,token,J.UNSAVED_CRASH_RECEIPT).exists()
            value=J.finalize_crash_off(root,quiet_seconds=0,codec_python=sys.executable)
            receipt=read(value['unsaved_crash_off_receipt']);assert receipt['kind']==J.UNSAVED_CRASH_KIND
            assert receipt['normal_save_completed']is False and receipt['mutations_may_be_unpersisted']is True
            assert 'normal_save_id'not in receipt and 'normal_save_witness'not in receipt
            assert receipt['original_business_recovery']['original_business_recovery_required']is True
            assert J._unsaved_crash_receipt_matches(root,scope,session,receipt)
            # Exact original core ownership gate using the new unsaved truth branch.
            code=(D/'source/installer/core.py').read_text();node=next(n for n in ast.parse(code).body if isinstance(n,ast.FunctionDef)and n.name=='_same_boot_generated_stop')
            env=dict(Path=Path,re=__import__('re'),owned_path=owned,read_json=read,marker=core.marker,fail=fail,digest=digest)
            exec(compile(ast.Module(body=[node],type_ignores=[]),'bounded-core','exec'),env)
            assert env['_same_boot_generated_stop'](root,{'profile':profile},{'profile':profile})[2]['normal_save_completed']is False
            # The named original rotator archives only events, and keeps all saved/WAL bytes.
            code=(D/'source/installer/standalone.py').read_text();node=next(n for n in ast.parse(code).body if isinstance(n,ast.FunctionDef)and n.name=='rotate_events')
            env=dict(Path=Path,get_state=core.get_state,read_json=read,fail=fail,owned_path=owned,time=time,
                operation_lock=core.operation_lock,ensure_no_session=core.ensure_no_session,digest=digest,atomic_json=atomic,os=os)
            exec(compile(ast.Module(body=[node],type_ignores=[]),'bounded-rotator','exec'),env)
            result=env['rotate_events'](root,value['unsaved_crash_off_receipt']);assert result['events_archive_only_no_replay_or_exactly_once_persistence_claim']and not events.exists()
        elif case==1:
            atomic(J._scope_path(root,token,'save-request.json'),{'synthetic_prior_submission':True})
            reject(lambda:J.finalize_crash_off(root,quiet_seconds=0), 'JOURNAL_CRASH_SAVE')
        elif case==2:
            host=root/'.palcraft/control'/f'{token}.host.json';row=read(host);row['job_active_processes']=1;atomic(host,row)
            reject(lambda:J.finalize_crash_off(root,quiet_seconds=0), 'JOURNAL_CRASH_HOST')
            row['job_active_processes']=0;atomic(host,row)
            live=subprocess.Popen([sys.executable,'-c','import time;time.sleep(1)'])
            try:
                s=read(root/'.palcraft/session.json');s['supervisor']={'pid':live.pid,'identity':'synthetic-owned:'+str(live.pid)};atomic(root/'.palcraft/session.json',s)
                reject(lambda:J.finalize_crash_off(root,quiet_seconds=0), 'JOURNAL_ACTOR_ALIVE')
            finally:live.wait()
            atomic(root/'.palcraft/session.json',session)
        else:
            atomic(level,{'uid':'00000000-0000-0000-0000-000000000002'})
            snapshots[level]=digest(level)
            reject(lambda:J.finalize_crash_off(root,quiet_seconds=0,codec_python=sys.executable), 'JOURNAL_CRASH_CODEC')
        assert all(digest(p)==value for p,value in snapshots.items())
print('PASS4 synthetic cases: real temporary original Popen wait + distinct unsaved receipt/core ownership/archive-only+WAL retained; saved submission refuses; active job/live supervisor refuses; wrong codec UID refuses. No Game Saved or real recovery executed.')
