"""Three bounded actual-function fixtures; synthetic codec data, no Game Saved."""
import ast, hashlib, json, os, subprocess, sys, tempfile, time
from pathlib import Path
D=Path(__file__).resolve().parents[1]
class Reject(Exception):
    def __init__(self,code,message,action=None):self.code,self.message,self.action=code,message,action
def fail(*args):raise Reject(*args)
def identity(p):
    s=p.stat();return {'device':s.st_dev,'inode':s.st_ino,'bytes':s.st_size,'mtime_ns':s.st_mtime_ns}
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def read(p):return json.loads(Path(p).read_text())
source=(D/'source/launcher/journal_lifecycle.py').read_text();tree=ast.parse(source)
nodes=[n for n in tree.body if isinstance(n,ast.FunctionDef)and n.name in ['_existing_level_codec','_late_normal_saved_level']]
with tempfile.TemporaryDirectory(prefix='synthetic-portable-codec-')as folder:
    root=Path(folder);uid='00000000-0000-0000-0000-000000000001';world='synthetic-world'
    level=root/'user/Saved/SaveGames/account'/world/'Level.sav';level.parent.mkdir(parents=True);level.write_text(json.dumps({'uid':uid}))
    player=level.parent/'Players'/f'{uid.replace("-","").upper()}.sav';player.parent.mkdir();player.write_text('{}')
    scope={'native_scope':{'world_id':world,'pal_uid':uid,'pid':1256},'normal_title_observed':{'synthetic_title':True}}
    profile={'standalone':{'save_account_directory':'account'}}
    selected=root/'.palcraft/standalone/scope.json';selected.parent.mkdir(parents=True);selected.write_text(json.dumps({'installed_level_path_host':str(level),'world_directory':world,'pal_uid':uid}))
    vendor=root/'dev/mcp/vendor/palworld_save_tools';vendor.mkdir(parents=True)
    (vendor/'__init__.py').write_text('')
    (vendor/'palsav.py').write_text('import ooz\ndef decompress_sav_to_gvas(data):return data,None\n')
    (vendor/'paltypes.py').write_text('PALWORLD_TYPE_HINTS={}\n')
    (vendor/'gvas.py').write_text('import json\nclass GvasFile:\n @staticmethod\n def read(data,*a,**kw):\n  uid=json.loads(data).get("uid","")\n  return type("Fixture",(),{"properties":{"worldSaveData":{"value":{"CharacterSaveParameterMap":{"value":[{"key":{"PlayerUId":{"value":uid}}}]}}}}})()\n')
    env=dict(Path=Path,json=json,os=os,subprocess=subprocess,time=time,USER='user',DEV='dev',owned_path=lambda r,n:r/n,
        read_json=read,file_identity=identity,digest=digest,fail=fail,get_state=lambda r:{'profile':profile})
    exec(compile(ast.Module(body=nodes,type_ignores=[]),'exact-source-codec-entry','exec'),env)
    facts={'profile':profile,'scope':scope};ooz=vendor.parent/'ooz.py'
    ooz.write_text('raise ModuleNotFoundError("No module named \'ooz\'")\n')
    before=(digest(level),digest(player))
    try:env['_existing_level_codec'](root,facts)
    except Reject as e:assert e.code=='JOURNAL_CODEC_DEPENDENCY'and'pyooz==0.0.8'in e.action and'--codec-python'in e.action
    else:raise AssertionError('Default missing dependency reported success')
    assert before==(digest(level),digest(player))
    # Explicit existing interpreter reaches the actual normal helper/standard reader branch.
    ooz.write_text('synthetic_available=True\n');now=time.time();os.utime(level,(now-1,now-1))
    host=root/'.palcraft/control/token.host.json';host.parent.mkdir(parents=True);host.write_text(json.dumps({'primary_pid':1256,'primary_alive':False,'job_active_processes':0,'exit_code':0,'phase':'stopped'}))
    witness={'normal_save_completed':True,'normal_save_id':'synthetic-original-save-id','level_mtime':now-5}
    session={'phase':'stopped','normal_stop_stage':'await_native_exit'};save={'submitted_unix':now-10}
    row=env['_late_normal_saved_level'](root,'token',scope,session,save,witness,level,codec_python=sys.executable)
    assert row['final_level_codec_observation']['codec_python_executable']==sys.executable
    assert row['original_early_witness_preserved']and row['normal_save_id']==witness['normal_save_id']
    assert before==(digest(level),digest(player))
    level.write_text(json.dumps({'uid':'wrong-synthetic-uid'}));wrong_before=digest(level)
    try:env['_existing_level_codec'](root,facts,codec_python=sys.executable)
    except Reject as e:assert e.code=='JOURNAL_CRASH_CODEC'
    else:raise AssertionError('Wrong UID accepted')
    assert digest(level)==wrong_before
print('PASS3 synthetic actual-function fixtures: default missingooz fails with pyooz0.0.8/explicit-python action; explicit existing Python flows through normal late helper and standard reader successfully; wrongUID rejects. Temp bytes preserved, no Game Saved/installer/software/runtime executed.')
