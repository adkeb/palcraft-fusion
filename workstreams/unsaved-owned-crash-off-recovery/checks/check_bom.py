"""One targeted synthetic CrashContext: UTF16 BOM plus UTF8 declaration."""
import ast, hashlib, re, tempfile, time
import xml.etree.ElementTree as ET
from pathlib import Path

D=Path(__file__).resolve().parents[1]
source=D/'source/launcher/journal_lifecycle.py'
tree=ast.parse(source.read_text())
facts=next(n for n in tree.body if isinstance(n,ast.FunctionDef)and n.name=='_crash_off_facts')
loop=next(n for n in facts.body if isinstance(n,ast.For)and isinstance(n.target,ast.Name)and n.target.id=='report')
oldtree=ast.parse((D/'base-v1/launcher/journal_lifecycle.py').read_text())
oldfacts=next(n for n in oldtree.body if isinstance(n,ast.FunctionDef)and n.name=='_crash_off_facts')
oldloop=next(n for n in oldfacts.body if isinstance(n,ast.For)and isinstance(n.target,ast.Name)and n.target.id=='report')
def identity(p):
 s=p.stat();return {'device':s.st_dev,'inode':s.st_ino,'bytes':s.st_size,'mtime_ns':s.st_mtime_ns}
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def fail(*args):raise AssertionError(args)
with tempfile.TemporaryDirectory(prefix='synthetic-crash-BOM-')as folder:
 root=Path(folder);crash=root/'Crashes/current';crash.mkdir(parents=True)
 report=crash/'CrashContext.runtime-xml'
 text='<?xml version="1.0" encoding="UTF-8"?><FGenericCrashContext><RuntimeProperties><ProcessId>1256</ProcessId><CrashType>Crash</CrashType><Description>合成编码边界</Description></RuntimeProperties></FGenericCrashContext>'
 report.write_bytes(text.encode('utf-16'));assert report.read_bytes().startswith(b'\xff\xfe')
 now=time.time();host=root/'host.json';host.write_text('{}');before=digest(report)
 env=dict(root=root,crash_dir=root/'Crashes',host_path=host,native={'pid':1256},scope={'started_unix':now-10},
  reports=[],owned_path=lambda r,n:r/n,file_identity=identity,digest=digest,fail=fail,ET=ET,re=re)
 exec(compile(ast.Module(body=[oldloop],type_ignores=[]),'v1-exact-loop','exec'),env)
 assert env['reports']==[], 'Fixture must reproduce the original false count0'
 exec(compile(ast.Module(body=[loop],type_ignores=[]),'v2-exact-loop','exec'),env)
 assert len(env['reports'])==1 and env['reports'][0]['relative_path']=='Crashes/current/CrashContext.runtime-xml'
 assert digest(report)==before and env['reports'][0]['sha256']==before
print('PASS1 targeted synthetic: exact original loop count0 reproduced for UTF16 BOM/UTF8 declaration; v2 Unicode loop uniquely matches samePID/current-window and preserves raw bytes. Other3 source branches not rerun; no actual Crash/Saved parsed.')
