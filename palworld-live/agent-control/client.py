"""Dependency-free autonomous BridgeLab control client. Payloads are JSON, no UI."""
import argparse,base64,json,subprocess,uuid,time
from pathlib import Path

def call(method,params=None,request_id=None):
    req={'id':request_id or str(uuid.uuid4()),'method':method,'params':params or {}}
    ps="$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue';[Console]::InputEncoding=[Text.Encoding]::UTF8;[Console]::OutputEncoding=New-Object Text.UTF8Encoding($false);& 'D:\PalworldServer-LAN\BridgeLab\Invoke-Agent.ps1'"
    encoded=base64.b64encode(ps.encode('utf-16le')).decode()
    command=['ssh','-T','-o','BatchMode=yes','-o','ConnectTimeout=10','-o','ServerAliveInterval=5','-o','ServerAliveCountMax=2','5090','powershell -NoProfile -NonInteractive -EncodedCommand '+encoded]
    for attempt in range(3):
        try:r=subprocess.run(command,input=json.dumps(req,ensure_ascii=False).encode(),capture_output=True,timeout=40,check=False)
        except subprocess.TimeoutExpired:
            if attempt==2:raise RuntimeError('Transport timeout; operation_id='+req['id']+'. Inspect this same operation ID before retrying.')
            time.sleep(.5);continue
        if r.returncode==0:break
        if attempt==2:raise RuntimeError('operation_id='+req['id']+'; '+r.stderr.decode('utf-8',errors='replace')[-3500:])
        time.sleep(.5)
    result=json.loads(r.stdout.decode('utf-8-sig'))
    if not result['ok']:raise RuntimeError(result['error'])
    return result['result']

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('method',choices=['status','operation','models','build','geometry','materials','catalog','dismantle','terrain','transform','finish','bases','storage','storage_plan','storage_apply','storage_operation','storage_cancel']);p.add_argument('params',nargs='?');p.add_argument('--request-id');a=p.parse_args()
    params=json.loads(Path(a.params).read_text()) if a.params else {}
    print(json.dumps(call(a.method,params,a.request_id),ensure_ascii=False,indent=2))
