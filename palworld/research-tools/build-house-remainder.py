from pathlib import Path
import subprocess,json,time,uuid,math,base64
R=Path(__file__).resolve().parents[1];L=R/'lab'
f=json.loads((L/'house-foundation-arm.json').read_text());p=f['position'];q=f['rotation'];yaw=2*math.atan2(q['Z'],q['W']);c=math.cos(yaw);s=math.sin(yaw)
remote='D:/PalworldServer-LAN/BridgeLab/rpc/'
def ps(code):
 a='powershell -NoProfile -NonInteractive -EncodedCommand '+base64.b64encode(('$ErrorActionPreference="Stop";$ProgressPreference="SilentlyContinue";'+code).encode('utf-16le')).decode()
 return subprocess.check_output(['ssh','-o','BatchMode=yes','5090',a],text=True)
parts=[('window-left','Wood_WindowWall',0,200,0,-math.pi/2),('window-right','Wood_WindowWall',0,-200,0,math.pi/2),('door','Wooden_DoorWall',200,0,0,math.pi),('roof','Wooden_roof',0,0,325,math.pi)]
for label,kind,x,y,z,turn in parts:
 cfg=dict(nonce=str(uuid.uuid4()),expires_unix=int(time.time())+300,base_id=f['base_id'],build_id=kind,position=dict(X=p['X']+x*c-y*s,Y=p['Y']+x*s+y*c,Z=p['Z']+z),rotation=dict(X=0,Y=0,Z=math.sin((yaw+turn)/2),W=math.cos((yaw+turn)/2)),archives=[],execute=True)
 path=L/f'house-{label}-arm.json'
 if path.exists():
  cfg=json.loads(path.read_text());print(json.dumps({'part':label,'resume_read_only':cfg['nonce']}),flush=True)
 else:
  path.write_text(json.dumps(cfg)+'\n')
  subprocess.run(['scp',str(path),'5090:'+remote+'house-experiment-arm.json'],check=True)
  ps("(Get-Item 'D:\\PalworldServer-LAN\\BridgeLab\\Pal\\Binaries\\Win64\\ue4ss\\Mods\\PalLiveBridge\\Scripts\\main.lua').LastWriteTime=Get-Date")
  print(json.dumps({'part':label,'activated':cfg['nonce']},ensure_ascii=False),flush=True)
  time.sleep(8)
 for i in range(12):
  raw=ps("$p='D:\\PalworldServer-LAN\\BridgeLab\\rpc\\house-experiment-"+cfg['nonce']+".json';if(Test-Path $p){[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes([IO.File]::ReadAllText($p)))}")
  if raw.strip():
   report=json.loads(base64.b64decode(raw.strip()).decode('utf-8'));(L/f'house-{label}-live.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
   if report.get('finished_unix'):
    print(json.dumps({'part':label,'status':report['status'],'model':report.get('new_model'),'errors':report.get('errors'),'before':report.get('materials_before',{}).get('totals'),'after':report.get('materials_immediate_after',{}).get('totals')},ensure_ascii=False),flush=True)
    if report['status']!='normal_structure_completed':raise SystemExit('Stopped after non-complete result')
    break
  time.sleep(3)
 else:raise SystemExit('No terminal report; stop without replay')
