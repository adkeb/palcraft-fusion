import ast,contextlib,hashlib,json,os,shutil,sys,tempfile,types
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
s=(ROOT/'source/installer/standalone.py').read_text()
node=next(x for x in ast.parse(s).body if isinstance(x,ast.FunctionDef) and x.name=='prepare_backend')
class Reject(Exception):pass
def fail(code,msg):raise Reject(code)
def digest(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def read(p,default=None):
 p=Path(p);return json.loads(p.read_text()) if p.exists() else default
def atomic(p,value):p=Path(p);p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(value))
runtime=types.ModuleType('launcher.runtime');runtime.process_matches=lambda record:record.get('alive')is True;runtime._port_free=lambda port:True
sys.modules['launcher']=types.ModuleType('launcher');sys.modules['launcher.runtime']=runtime
with tempfile.TemporaryDirectory()as folder:
 root=Path(folder)/'player';backend=Path(folder)/'backend';root.mkdir()
 profile={'standalone':{'backend_root':str(backend)}}
 source=root/'dev/minecraft-mods/mod.jar';source.parent.mkdir(parents=True);source.write_bytes(b'new')
 cfg={'mod_filename':'mod.jar','mod_sha256':digest(source),'guest_game_dir':str(backend/'guest')}
 atomic(root/'tools/standalone/mac-runtime-config.json',cfg)
 destinations=[backend/'mods/mod.jar',backend/'server/mods/mod.jar',backend/'guest/mods/mod.jar']
 for d in destinations:d.parent.mkdir(parents=True,exist_ok=True);d.write_bytes(b'old')
 atomic(root/'.palcraft/standalone/backend-files.json',{'backend_root':str(backend),'files':[{'path':str(d),'sha256':digest(d)}for d in destinations]})
 session={'launch_mode':'singleplayer-bootstrap','phase':'bootstrap','supervisor':{'alive':True},'components':{'client':{'alive':True}}}
 atomic(root/'.palcraft/session.json',session)
 env={'Path':Path,'get_state':lambda r:{'profile':profile},'TOOLS':'tools','DEV':'dev','read_json':read,'digest':digest,
 'operation_lock':lambda r:contextlib.nullcontext(),'ensure_no_session':lambda r:fail('ACTIVE','rejectlive'),'fail':fail,
 'atomic_json':atomic,'os':os,'shutil':shutil}
 exec(compile(ast.Module(body=[node],type_ignores=[]),'original-prepare','exec'),env)
 result=env['prepare_backend'](root);assert result['ok'] and all(d.read_bytes()==b'new'for d in destinations)
 record=root/'.palcraft/standalone/backend-files.json';record.unlink()
 for d in destinations:d.write_bytes(b'old')
 old_sha=digest(destinations[0]);target='dev/minecraft-mods/mod.jar'
 transaction=root/'.palcraft/transactions/fixture'
 backup=transaction/'before'/target;backup.parent.mkdir(parents=True);backup.write_bytes(b'old')
 atomic(transaction/'journal.json',{'phase':'committed','before_state':{'profile':profile,'manifest':{'files':[{'role':'minecraft_mod','target':target,'sha256':old_sha}]}},
   'changes':[{'target':target,'old_sha256':old_sha,'new_sha256':digest(source)}]})
 assert env['prepare_backend'](root)['ok'] and all(d.read_bytes()==b'new' for d in destinations)
 session['components']['hud']={'alive':True};atomic(root/'.palcraft/session.json',session)
 try:env['prepare_backend'](root)
 except Reject as e:assert str(e)=='BACKEND_ACTIVE'
 else:raise AssertionError('livebackendreplaced')
 session['components'].pop('hud');atomic(root/'.palcraft/session.json',session);destinations[0].write_bytes(b'foreign')
 try:env['prepare_backend'](root)
 except Reject as e:assert str(e)=='BACKEND_MOD_EXISTS'
 else:raise AssertionError('foreignmodoverwritten')
 assert destinations[0].read_bytes()==b'foreign' and destinations[1].read_bytes()==b'new'
print('PASS4: originalownedcopies; exactcommittedbeforemod baseline adoption; livebackendreject; foreignbytesrejectpreflight.')
