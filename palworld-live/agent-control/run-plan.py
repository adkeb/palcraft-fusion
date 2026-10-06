"""Apply a saved plan serially, keeping operation UUIDs and actual model IDs."""
from pathlib import Path
import json,sys,time,uuid
from client import call
import base64,subprocess

plan_path=Path(sys.argv[1]);plan=json.loads(plan_path.read_text());report_path=plan_path.with_name(plan_path.stem+'-run.json')
report=json.loads(report_path.read_text()) if report_path.exists() else {'plan':str(plan_path),'status':'running','rows':[]}
def save():report_path.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
def save_world():
    ps=r'''$ProgressPreference='SilentlyContinue';$ErrorActionPreference='Stop';$r='D:\PalworldServer-LAN\BridgeLab';$ini=[IO.File]::ReadAllText("$r\Pal\Saved\Config\WindowsServer\PalWorldSettings.ini");$pw=[regex]::Match($ini,'AdminPassword="([^"\r\n]+)"').Groups[1].Value;$h=@{Authorization='Basic '+[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('admin:'+$pw))};Invoke-RestMethod 'http://127.0.0.1:8322/v1/api/save' -Headers $h -Method Post|Out-Null'''
    encoded=base64.b64encode(ps.encode('utf-16le')).decode();subprocess.run(['ssh','-o','BatchMode=yes','5090','powershell -NoProfile -NonInteractive -EncodedCommand '+encoded],check=True,capture_output=True)
for index,op in enumerate(plan['operations']):
    if index<len(report['rows']) and report['rows'][index].get('status')=='completed':continue
    if index==len(report['rows']):report['rows'].append({'index':index,'label':op['label'],'id':str(uuid.uuid4()),'status':'starting'})
    row=report['rows'][index];save()
    if op['kind']=='dismantle':
        result=call('dismantle',op['params'],row['id']);time.sleep(.3)
        remaining=call('models',{'ids':op['params']['ids']})['models']
        row['result']=result;row['remaining']=remaining
        if remaining:report['status']='stopped';save();raise SystemExit('Some requested objects were not removed; inspect their IDs.')
        row['status']='completed';save();print(f'{index+1}/{len(plan["operations"])} {op["label"]}: removed',flush=True);continue
    receipt=call('build',op['params'],row['id']);row['receipt']=receipt;save()
    for _ in range(150):
        result=call('operation',{'id':row['id']});row['result']=result
        status=result.get('status')
        if status=='completed' or status=='registered_work_pending':break
        if status in ('failed','spawn_not_observed'):report['status']='stopped';save();raise SystemExit(op['label']+': '+result.get('error',status))
        time.sleep(.3)
    else:report['status']='awaiting_operation';save();raise SystemExit('Operation remains unresolved: '+row['id'])
    row['status']='completed' if status=='completed' else 'registered_work_pending';save();print(f'{index+1}/{len(plan["operations"])} {op["label"]}: {status}',flush=True)
    if (index+1)%10==0:save_world()
report['status']='completed' if all(r['status']=='completed' for r in report['rows']) else 'work_pending';save();save_world()
