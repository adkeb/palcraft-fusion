#!/usr/bin/env python3
"""Launch this owned Game to observe a real Standalone realm; integration remains pending."""
import json,sys,uuid,time,os
from pathlib import Path
root=Path('/path/to/PalCraft')
sys.path.insert(0,str(root/'PalCraft-Dev/player-tools'))
from installer.core import operation_lock,ensure_no_session,atomic_json
from launcher.runtime import Session,command_plan,process_identity
with operation_lock(root):
 ensure_no_session(root)
 token=uuid.uuid4().hex
 atomic_json(root/'.palcraft/session.json',{'schema':1,'token':token,'phase':'starting','components':{},'started_unix':time.time(),'startup_mode':'standalone-native-observation','integration_ready_claimed':False})
 commands=command_plan(root,token)['commands']
s=Session(root,token,commands=commands)
s.save('bootstrap-singleplayer',message='Native Standalone observation only; MC/AI/HUD integration remains pending.')
s.beat();game=s.spawn('client');s.save('bootstrap-singleplayer',integration_ready_claimed=False)
print(json.dumps({'ok':True,'mode':'standalone-native-observation','game_process_started':True,'game_ready':False,'MC_AI_HUD_complete':False,'other_games_started':False}),flush=True)
while game.poll() is None:
 s.beat();time.sleep(s.poll_seconds)
result=s.finish('stopped' if game.returncode==0 else 'failed','OK' if game.returncode==0 else 'CLIENT_EXIT','Standalone observation game exited normally.' if game.returncode==0 else 'Standalone observation game exited with error.')
print(json.dumps(result,ensure_ascii=False),flush=True)
