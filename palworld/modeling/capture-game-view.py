"""Read the existing Palworld game window through SSH, without input or focus.

Uses a short-lived interactive Windows task because the SSH service is in
session 0. Captures only the game client area; does not open or restart games.
"""
import base64
import datetime
import fcntl
import json
from pathlib import Path
import subprocess
import uuid

HERE = Path(__file__).resolve().parent
OUT = HERE.parents[2] / 'outputs' / 'villa-game-view'
OUT.mkdir(parents=True, exist_ok=True)

def remote(script):
    encoded=base64.b64encode(script.encode('utf-16le')).decode()
    subprocess.run(['ssh','-o','BatchMode=yes','-o','ConnectTimeout=15','5090',
                    'powershell -NoProfile -NonInteractive -EncodedCommand '+encoded],check=True)

with (HERE/'capture-game-view.lock').open('w') as lock:
    fcntl.flock(lock,fcntl.LOCK_EX)
    task='Palworld-View-'+str(uuid.uuid4())
    stamp=datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=8))).strftime('%Y%m%d-%H%M%S')
    remote(r'''
$ErrorActionPreference='Stop';$ProgressPreference='SilentlyContinue'
$p='D:\PalworldServer-LAN\BridgeLab\view\capture-status.json'
if(Test-Path $p){Remove-Item -LiteralPath $p}
$name='TASK_NAME'
$action=New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Argument '-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "D:\PalworldServer-LAN\BridgeLab\view\Capture-PalworldWindow.ps1"'
$principal=New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited
$settings=New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 1)
try {
 Register-ScheduledTask -TaskName $name -Action $action -Principal $principal -Settings $settings|Out-Null
 Start-ScheduledTask -TaskName $name
 for($i=0;$i -lt 40;$i++){if(Test-Path $p){break};Start-Sleep -Milliseconds 500}
 if(!(Test-Path $p)){throw 'Capture task did not return a report'}
} finally {Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction SilentlyContinue}
'''.replace('TASK_NAME',task))
    status_path=OUT/('capture-status-'+stamp+'.json')
    subprocess.run(['scp','-q','5090:D:/PalworldServer-LAN/BridgeLab/view/capture-status.json',str(status_path)],check=True)
    status=json.loads(status_path.read_text(encoding='utf-8-sig'))
    if status['status']!='captured':
        raise SystemExit(json.dumps(status,ensure_ascii=False))
    destination=OUT/('palworld-window-'+stamp+'.png')
    subprocess.run(['scp','-q','5090:D:/PalworldServer-LAN/BridgeLab/view/palworld-window.png',str(destination)],check=True)
    print(json.dumps({'path':str(destination.resolve()),**status},ensure_ascii=False))
