from pathlib import Path
s=Path('work/palworld-live/research/test-lab-worker-active-preflight.lua').read_text().split('function FindAllOf(class)')[0]
s=s.replace('lab-worker-active-preflight','lab-worker-assign-once')
s=s.replace("local files,queue,classes,paths,counts,frame,mode,clock_now,in_game", "local PREFIX='D:/PalworldServer-LAN/BridgeLab/rpc/lab-worker-assign-once'\nlocal PLAYER='22222222-0000-0000-0000-000000000000';local IID='00000000-0000-4000-8000-00000000002e'\nlocal files,queue,classes,paths,counts,frame,mode,clock_now,in_game,delays,assigned_state")
s=s.replace("R.guid_from_string(guid(i))", "R.guid_from_string(i==2 and IID or guid(i))")
s=s.replace("clock_now=0;in_game=false", "clock_now=0;in_game=false;delays={};assigned_state=false")
s=s.replace("GetHungerType=function()return 0 end", "GetPhysicalHealth=function()return 0 end,GetWorkSuitabilityRankWithCharacterRank=function(_,v)assert(v==5);return 6 end,GetHungerType=function()return 0 end")
s=s.replace("IsAssignedToAnyWork=function()return mode=='busy'end,IsAssignedFixed=function()return false end,GetWorkId=function()return R.guid_from_string(mode=='busy'and WORK or ZERO)end", "IsAssignedToAnyWork=function()return mode=='busy'or assigned_state end,IsAssignedFixed=function()return assigned_state end,GetWorkId=function()return R.guid_from_string((mode=='busy'or assigned_state)and WORK or ZERO)end,GetWorkAssign=function()return paths['/Game/Test.Assignment']end")
s=s.replace("GetCharacterParameter=function()return cp end,GetPawn", "RegisterFixedAssignWork=function(_,g)\n    assert(in_game and frame==4 and i==2 and R.guid_to_string(g)==WORK)\n    assert(files[PREFIX..'.intent.json']and files[PREFIX..'.used-arm.json']and not files[PREFIX..'.arm.json'],'WRITE BEFORE COMMITTED INTENT/CLAIM')\n    counts.writes=(counts.writes or 0)+1;assert(counts.writes==1,'AUTO REPLAY')\n    if mode=='native_error'then error('native error')end\n    assigned_state=mode~='native_noop'\n   end,GetCharacterParameter=function()return cp end,GetPawn")
s=s.replace("GetWorkId=function()return R.guid_from_string(WORK)end,GetAssignableFixedType", "GetAssignedCharacters=function(_,out)counts.target_checks=(counts.target_checks or 0)+1;if mode=='occupied'then out[1]={get=function()error('MUST NOT NEED SLOT CONTENT')end}end end,\n  IsAssignedCharacter=function(_,h)assert(R.guid_to_string(h:GetIndividualID().InstanceId)==IID);return assigned_state and mode~='reverse_binding_false'end,\n  GetWorkId=function()return R.guid_from_string(WORK)end,GetAssignableFixedType")
s=s.replace(" classes.PalBaseCampManager={bm};classes.PalMapObjectManager={mm}\nend", """ classes.PalBaseCampManager={bm};classes.PalMapObjectManager={mm}
 local pc,state,pawn,tx,guild
 guild=obj('PalGroupGuild','Guild',{GetId=function()return R.guid_from_string(GUILD)end,HasGuildPermission=function(_,uid,permission)
  assert(R.guid_to_string(uid)==PLAYER and permission==7,'wrong player/permission');counts.permissions=(counts.permissions or 0)+1
  return mode~='permission_denied'and not(mode=='permission_changed'and frame==4)
 end})
 state=obj('PalPlayerState','PS',{GetPlayerController=function()return pc end,GuildBelongTo=guild})
 pawn=obj('PalPlayerCharacter','Pawn',{HasAuthority=function()return true end,GetController=function()return pc end})
 tx=obj('PalNetworkTransmitter','TX',{GetOwner=function()return pc end})
 pc=obj('PalPlayerController','PC',{GetPlayerUId=function()return R.guid_from_string(PLAYER)end,HasAuthority=function()return true end,
  IsPlayerController=function()return true end,NetConnection=obj('NetConnection','Conn',{}),GetPalPlayerState=function()return state end,
  GetDefaultPlayerCharacter=function()return pawn end,Transmitter=tx})
 classes.PalPlayerController={pc}
 obj('PalWorkAssign','Assignment',{GetAssignedIndividualId=function()return identity(2)end,GetWork=function()return work end,
  IsWorking=function()return false end,IsWorkable=function()return false end,GetState=function()return 0 end,GetWorkingState=function()return 3 end})
 files[PREFIX..'.arm.json']=J.encode({lab_only=true,action='assign-zoe-old-workbench-once',nonce='00000000-0000-4000-8000-000000000019',
  expires_unix=mode=='expired'and 999 or 1100,base_id=BASE,work_id=WORK,individual_id=IID,player_uid=PLAYER})
end""")
s+='''
function FindAllOf(class)
 assert(in_game and classes[class],'unapproved global scan')
 counts[class]=(counts[class]or 0)+1;assert(counts[class]==1,'repeated global scan');return classes[class]
end
function StaticFindObject(path)assert(in_game);counts.lookup=(counts.lookup or 0)+1;return paths[path]end
function ExecuteWithDelay(ms,fn)
 assert(ms==50 or ms==3000 or ms==7000);delays[#delays+1]=ms;queue[#queue+1]=fn
end
function ExecuteInGameThread(fn)assert(not in_game);in_game=true;fn();in_game=false end
function IsInGameThread()return in_game end
dofile=function(path)if path:match('json.lua$')then return J elseif path:match('readers.lua$')then return R end;error(path)end
debug.getinfo=function()return{source=SOURCE}end
io.open=function(path,m)
 assert(path:find('BridgeLab',1,true)and(m=='ab'or m=='wb'or m=='rb'))
 if m=='rb'then if files[path]==nil then return nil end;return{read=function(_,n)return files[path]:sub(1,n)end,close=function()return true end}end
 if m=='wb'then files[path]=''end
 return{write=function(_,v)files[path]=(files[path]or'')..v;return true end,
  flush=function()return not(mode=='intent_flush_error'and path==PREFIX..'.intent.json.tmp')end,close=function()return true end}
end
os.remove=function()error('MUST NOT DELETE EVIDENCE')end
os.rename=function(a,b)assert(files[b]==nil,'OVERWRITE');files[b]=assert(files[a]);files[a]=nil;return true end
os.time=function()return 1000 end
os.clock=function()if mode=='time_limit'then clock_now=clock_now+.1 end;return clock_now end
local function drain()while #queue>0 do frame=frame+1;assert(frame<=6);table.remove(queue,1)()end end
local function run(m)
 fixture(m);probe();assert(next(counts)==nil,'eager native work');drain()
 return J.decode(assert(files[PREFIX..'.result.json']))
end
local n=0;local function test(name,fn)fn();n=n+1;print('PASS '..name)end
test('one normal fixed call durable intent before write and two delayed bilateral reads',function()
 local r=run('ready');assert(r.ok and r.complete and r.native_call_attempted and r.native_call_returned)
 assert(counts.writes==1 and counts.permissions==2 and counts.target_checks==1)
 assert(#r.callbacks==6 and delays[5]==3000 and delays[6]==7000 and #r.observations==2)
 for _,v in ipairs(r.observations)do assert(v.matches_target and v.task.work_recognizes_character and not v.task.working and v.task.working_state_enum==3)end
 assert(files[PREFIX..'.intent.json']and files[PREFIX..'.used-arm.json']and not files[PREFIX..'.arm.json'])
 assert(counts.PalBaseCampManager==1 and counts.PalMapObjectManager==1 and counts.PalPlayerController==1)
end)
test('occupied target rejects without releasing another worker or committing intent',function()
 local r=run('occupied');assert(not r.ok and not r.native_call_attempted and not counts.writes and not files[PREFIX..'.intent.json'])
 assert(r.error:find('replacing workers is forbidden',1,true))
end)
test('permission checked on apply callback and expired/busy/sleeping/invalid reject',function()
 for _,m in ipairs({'permission_denied','permission_changed','expired','busy','sleeping','paused','unloaded','bad_priority','cycle','foreign_worker','unregistered','waiting','time_limit'})do
  local r=run(m);assert(not r.ok and not counts.writes and not r.native_call_attempted and not files[PREFIX..'.intent.json'],m)
 end
end)
test('void no-op native error or one-sided readback never claims success or retries',function()
 for _,m in ipairs({'native_noop','native_error','reverse_binding_false'})do
  local r=run(m);assert(not r.ok and r.status=='needs_inspection'and counts.writes==1 and r.native_call_attempted,m)
 end
end)
test('intent flush failure preserves partial evidence and prevents native call',function()
 local r=run('intent_flush_error');assert(not r.ok and not counts.writes and files[PREFIX..'.intent.json.tmp'])
 local before=files[PREFIX..'.result.json'];probe();assert(#queue==0 and files[PREFIX..'.result.json']==before and not counts.writes)
end)
test('reload after completion preserves result and does not scan or replay',function()
 run('ready');local before=files[PREFIX..'.result.json'];local calls=counts.lookup;probe()
 assert(#queue==0 and counts.writes==1 and counts.lookup==calls and files[PREFIX..'.result.json']==before)
end)
test('orphan intent and observation block startup without needing valid JSON',function()
 for _,suffix in ipairs({'.intent.json','.intent.json.tmp','.after-3s.json','.after-10s.json.tmp','.used-arm.json','.call-returned.json'})do
  fixture('ready');files[PREFIX..suffix]='interrupted write';probe();assert(#queue==0 and next(counts)==nil and not files[PREFIX..'.result.json'])
 end
end)
test('production path rejects before scheduling scanning or mutation',function()
 fixture('ready');SOURCE='@D:/steam/steamapps/common/PalServer/Pal/Binaries/Win64/ue4ss/Mods/PalLiveBridge/Scripts/probe.lua'
 assert(not pcall(probe)and #queue==0 and next(counts)==nil)
end)
print('OK '..n..' LOCAL MOCK once-assignment groups; no actual assignment or production support claim')
'''
Path('work/palworld-live/research/test-lab-worker-assign-once.lua').write_text(s)
