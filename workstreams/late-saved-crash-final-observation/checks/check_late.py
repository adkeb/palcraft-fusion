import ast,hashlib,json,os,tempfile,time
from pathlib import Path
HERE=Path(__file__).resolve().parents[1]
source=(HERE/'source/launcher/journal_lifecycle.py').read_text()
tree=ast.parse(source);node=next(n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name=='_late_saved_level')
class Reject(Exception):pass
def fail(code,message):raise Reject(code)
def read(path):return json.loads(Path(path).read_text())
def file_identity(path):
 s=Path(path).stat();return {'device':s.st_dev,'inode':s.st_ino,'bytes':s.st_size,'mtime_ns':s.st_mtime_ns}
def digest(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
class CodecProcess:
 @staticmethod
 def run(*args,**kwargs):
  return type('Result',(),{'returncode':0,'stdout':json.dumps({'parsed':True,'owned_uid_present':True})})()
namespace={'json':json,'subprocess':CodecProcess,'Path':Path,'file_identity':file_identity,'read_json':read,'owned_path':lambda r,n:r/n,'digest':digest,'fail':fail,'USER':'private-user','DEV':'private-tools','time':time,'re':__import__('re')}
exec(compile(ast.Module(body=[node],type_ignores=[]),'original-helper','exec'),namespace)
with tempfile.TemporaryDirectory()as folder:
 root=Path(folder);token='a'*32;pid=999
 level=root/'private-user/Saved/SaveGames/account/world/Level.sav';level.parent.mkdir(parents=True);level.write_bytes(b'final-level')
 player=level.parent/'Players/00000000000000000000000000000001.sav';player.parent.mkdir();player.write_bytes(b'player')
 now=time.time();os.utime(level,(now-3,now-3))
 native={'pid':pid,'world_id':'world','pal_uid':'00000000-0000-0000-0000-000000000001','process_epoch':'fixture','save_boot_id':'fixture'}
 host_path=root/'.palcraft/control'/f'{token}.host.json';host_path.parent.mkdir(parents=True)
 host={'primary_pid':pid,'primary_alive':False,'job_active_processes':0,'exit_code':3,'phase':'failed'}
 host_path.write_text(json.dumps(host));os.utime(host_path,(now-1,now-1))
 report=root/'private-user/Saved/Crashes/fixture/CrashContext.runtime-xml';report.parent.mkdir(parents=True)
 report.write_text('<root><ProcessId>999</ProcessId><CrashType>Crash</CrashType></root>');os.utime(report,(now-2,now-2))
 witness={'level_mtime':now-5,'normal_save_id':'fixture-save'}
 save={'submitted_unix':now-6};scope={'native_scope':native,'started_unix':now-20};session={'stopped_unix':now-1}
 proof={'schema':1,'codec_parse_succeeded':True,'standard_original_codec':'palworld_save_tools decompress_sav_to_gvas + GvasFile.read PALWORLD_TYPE_HINTS',
  'Level_bytes':level.stat().st_size,'Level_sha256':digest(level),'owned_path_world_id':'world','uid1_exists_in_CharacterSaveParameterMap':True,
  'uid1_PlayerSav_exists':True,'uid1_PlayerSav_bytes':player.stat().st_size,'same_normal_save_id':'fixture-save','same_native_scope':native,
  'save_or_side_effects':False,'observed_unix':now,'codec_python_executable':__import__('sys').executable}
 codec=root/'codec.json';codec.write_text(json.dumps(proof));os.environ['PALCRAFT_LATE_LEVEL_CODEC_PROOF']=str(codec)
 original=dict(witness)
 result=namespace['_late_saved_level'](root,token,scope,session,save,witness,level)
 assert result['original_early_witness_preserved'] and witness==original and result['level_sha256']==digest(level)
 os.utime(level,(now+1,now+1))
 try:namespace['_late_saved_level'](root,token,scope,session,save,witness,level)
 except Reject as e:assert str(e)=='JOURNAL_SAVE_CHANGED'
 else:raise AssertionError('post-crash edit accepted')
 os.utime(level,(now-3,now-3));proof['codec_parse_succeeded']=False;codec.write_text(json.dumps(proof))
 try:namespace['_late_saved_level'](root,token,scope,session,save,witness,level)
 except Reject as e:assert str(e)=='JOURNAL_SAVE_CHANGED'
 else:raise AssertionError('invalid final save accepted')
assert "if not saved_crash:\n                fail('JOURNAL_SAVE_CHANGED'" in source
print('PASS 3 targeted cases: originalearlywitness retained + lateprecrash parsedfile accepted; postcrash edit rejected; failedcodec rejected. Normal0 remains strict.')
