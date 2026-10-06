-- Local mocks; actual native acceptance remains a separate Lab-only action.
local J=dofile('work/palworld-live/bridge/PalLiveBridge/Scripts/json.lua')
local R=dofile('work/palworld-live/bridge/PalLiveBridge/Scripts/readers.lua')
local probe=assert(loadfile('work/palworld-live/lab/lab-worker-assign-once.lua'))
local BASE='00000000-0000-4000-8000-000000000031';local GUILD='00000000-0000-4000-8000-00000000001b'
local MODEL='00000000-0000-4000-8000-000000000012';local WORK='00000000-0000-4000-8000-000000000020'
local ZERO='00000000-0000-0000-0000-000000000000';local CID='00000000-0000-4000-8000-000000000001'
local SOURCE='@D:/PalworldServer-LAN/BridgeLab/Pal/Binaries/Win64/ue4ss/Mods/PalLiveBridge/Scripts/lab-worker-assign-once.lua'
local PREFIX='D:/PalworldServer-LAN/BridgeLab/rpc/lab-worker-assign-once'
local PLAYER='22222222-0000-0000-0000-000000000000';local IID='00000000-0000-4000-8000-00000000002e'
local files,queue,classes,paths,counts,frame,mode,clock_now,in_game,delays,assigned_state
local function obj(class,name,p,extra)
 p=p or{};local full=class..' /Game/Test.'..name
 p.IsValid=function()return true end;p.GetFullName=function()return full end
 p.IsA=function(_,s)return s=='/Script/Pal.'..class or(extra and extra[s])or false end
 local o=setmetatable(p,{__index=function(_,k)error('UNEXPECTED '..name..'.'..k)end})
 paths['/Game/Test.'..name]=o;return o
end
local function guid(v)return string.format('00000000-0000-0000-0000-%012x',v)end
local function identity(i)return{InstanceId=R.guid_from_string(i==2 and IID or guid(i)),PlayerUId=R.guid_from_string(ZERO)}end
local function fixture(m)
 mode=m;files={};queue={};classes={};paths={};counts={};frame=0;clock_now=0;in_game=false;delays={};assigned_state=false
 local base,director,work,concrete,module
 local slots={}
 for i=1,5 do
  local parameter,actor,cp,controller,component,top,root,worker
  parameter=obj('PalIndividualCharacterParameter','P'..i,{
   GetPalId=function()return identity(i)end,GetBaseCampId=function()return R.guid_from_string(BASE)end,GetGroupId=function()return R.guid_from_string(mode=='foreign_worker'and BASE or GUILD)end,
   GetCharacterID=function()return'Lamball'end,GetLevel=function()return 10 end,IsDead=function()return false end,IsSleeping=function()return mode=='sleeping'end,
   GetPhysicalHealth=function()return 0 end,GetWorkSuitabilityRankWithCharacterRank=function(_,v)assert(v==5);return 6 end,GetHungerType=function()return 0 end,GetWorkerSick=function()return 0 end,GetSanityValue=function()return 90 end})
  cp=obj('PalCharacterParameterComponent','CP'..i,{GetIndividualParameter=function()return parameter end,
   IsAssignedToAnyWork=function()return mode=='busy'or assigned_state end,IsAssignedFixed=function()return assigned_state end,GetWorkId=function()return R.guid_from_string((mode=='busy'or assigned_state)and WORK or ZERO)end,GetWorkAssign=function()return paths['/Game/Test.Assignment']end})
  actor=obj('PalCharacter','A'..i,{HasAuthority=function()return mode~='no_authority'end,GetCharacterParameterComponent=function()return cp end,GetController=function()return controller end})
  controller=obj('PalAIController','C'..i,{HasAuthority=function()return true end,Pawn=actor})
  component=obj('PalAIActionComponent','Comp'..i,{GetOwner=function()return controller end,ControlledPawn=mode=='wrong_component_pawn'and parameter or actor,
   GetCurrentTopParentAction_BP=function()return top end,GetCompositeRoot=function(_,priority)
    local actual=mode=='priority_one'and 1 or 10;assert(priority==actual,'PRIORITY WAS GUESSED OR OMITTED');counts.priorities=(counts.priorities or 0)+1;return root
   end})
  controller.AIActionComponent=component
  top=obj('PawnAction','Top'..i,{OwnerComponent=component,GetActionPriority=function()return mode=='bad_priority'and 7 or mode=='priority_one'and 1 or 10 end},{['/Script/AIModule.PawnAction']=true})
  worker=obj('PalAIActionCompositeWorker','Worker'..i,{GetOwnerComponent=function()return component end,IsPaused=function()return mode=='paused'end,
   RegisterFixedAssignWork=function(_,g)
    assert(in_game and frame==4 and i==2 and R.guid_to_string(g)==WORK)
    assert(files[PREFIX..'.intent.json']and files[PREFIX..'.used-arm.json']and not files[PREFIX..'.arm.json'],'WRITE BEFORE COMMITTED INTENT/CLAIM')
    counts.writes=(counts.writes or 0)+1;assert(counts.writes==1,'AUTO REPLAY')
    if mode=='native_error'then error('native error')end
    assigned_state=mode~='native_noop'
   end,GetCharacterParameter=function()return cp end,GetPawn=function()return actor end,GetChild=function()if mode=='cycle'then return root end;return nil end},
   {['/Script/Pal.PalAIActionCompositeBase']=true})
  root=obj('PalAIActionCompositeBase','Root'..i,{GetOwnerComponent=function()return component end,IsPaused=function()return false end,GetChild=function()return worker end})
  local handle=obj('PalIndividualCharacterHandle','H'..i,{GetIndividualID=function()
   counts.identity_reads=(counts.identity_reads or 0)+1;if mode=='replaced'and frame>1 then return identity(i+20)end;return identity(i)
  end,TryGetIndividualParameter=function()return parameter end,TryGetIndividualActor=function()
   counts.actor_reads=(counts.actor_reads or 0)+1;if mode=='unloaded'then return nil end;return actor
  end})
  local slot=obj('PalIndividualCharacterSlot','S'..i,{IsEmpty=function()return false end,GetHandle=function()return handle end,GetSlotIndex=function()return i-1 end})
  slots[#slots+1]={get=function()return slot end}
 end
 director=obj('PalBaseCampWorkerDirector','Director',{BaseCampId=R.guid_from_string(BASE),State=mode=='waiting'and 1 or 2,GetOuter=function()return base end,
  GetCharacterHandleSlots=function(_,out)for i,s in ipairs(slots)do out[i]=s end end})
 base=obj('PalBaseCampModel','Base',{WorkerDirector=director,IsAvailable=function()return true end,GetId=function()return R.guid_from_string(BASE)end,GetGroupIdBelongTo=function()return R.guid_from_string(GUILD)end})
 local bm=obj('PalBaseCampManager','BM',{TryGetModel=function(_,g,out)assert(R.guid_to_string(g)==BASE);out.OutModel=base;return true end})
 work=obj('PalWorkBase','Work',{BaseCampIdBelongTo=R.guid_from_string(BASE),OwnerMapObjectModelId=R.guid_from_string(MODEL),OwnerMapObjectConcreteModelId=R.guid_from_string(CID),
  GetAssignedCharacters=function(_,out)counts.target_checks=(counts.target_checks or 0)+1;if mode=='occupied'then out[1]={get=function()error('MUST NOT NEED SLOT CONTENT')end}end end,
  IsAssignedCharacter=function(_,h)assert(R.guid_to_string(h:GetIndividualID().InstanceId)==IID);return assigned_state and mode~='reverse_binding_false'end,
  GetWorkId=function()return R.guid_from_string(WORK)end,GetAssignableFixedType=function()return 0 end,GetWorkName=function()return'手工作业'end,
  IsExistAssignableSlot=function(_,h,fixed)assert(fixed==true and h:IsA('/Script/Pal.PalIndividualCharacterHandle'));counts.native=(counts.native or 0)+1;return mode~='unsuitable'end})
 module=obj('PalMapObjectWorkeeModule','Module',{TargetWork=work,GetOuter=function()return concrete end,GetWork=function()return work end})
 local registered=false
 local function guard(v)return function()assert(registered,'DEPENDENT GETTER BEFORE REGISTRATION');return v()end end
 concrete=obj('PalMapObjectConcreteModelBase','Concrete',{bDisposed=false,
  GetModelInstanceId=guard(function()return R.guid_from_string(MODEL)end),GetBaseCampIdBelongTo=guard(function()return R.guid_from_string(BASE)end),
  GetBaseCampModelBelongTo=guard(function()return base end),GetWorkeeModule=guard(function()return module end),GetInstanceId=guard(function()return R.guid_from_string(CID)end)})
 local model=obj('PalMapObjectModel','Model',{BuildObjectId='Workbench',GetConcreteModel=function(_,force)assert(force==false and registered);return concrete end})
 local mm=obj('PalMapObjectManager','MM',{FindModel=function(_,g)assert(R.guid_to_string(g)==MODEL);if mode=='unregistered'then return nil end;registered=true;return model end})
 classes.PalBaseCampManager={bm};classes.PalMapObjectManager={mm}
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
end

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
