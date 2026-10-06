-- Local mocks; actual native acceptance remains a separate Lab-only action.
local J=dofile('work/palworld-live/bridge/PalLiveBridge/Scripts/json.lua')
local R=dofile('work/palworld-live/bridge/PalLiveBridge/Scripts/readers.lua')
local probe=assert(loadfile('work/palworld-live/lab/lab-worker-active-preflight.lua'))
local BASE='00000000-0000-4000-8000-000000000031';local GUILD='00000000-0000-4000-8000-00000000001b'
local MODEL='00000000-0000-4000-8000-000000000012';local WORK='00000000-0000-4000-8000-000000000020'
local ZERO='00000000-0000-0000-0000-000000000000';local CID='00000000-0000-4000-8000-000000000001'
local SOURCE='@D:/PalworldServer-LAN/BridgeLab/Pal/Binaries/Win64/ue4ss/Mods/PalLiveBridge/Scripts/lab-worker-active-preflight.lua'
local files,queue,classes,paths,counts,frame,mode,clock_now,in_game
local function obj(class,name,p,extra)
 p=p or{};local full=class..' /Game/Test.'..name
 p.IsValid=function()return true end;p.GetFullName=function()return full end
 p.IsA=function(_,s)return s=='/Script/Pal.'..class or(extra and extra[s])or false end
 local o=setmetatable(p,{__index=function(_,k)error('UNEXPECTED '..name..'.'..k)end})
 paths['/Game/Test.'..name]=o;return o
end
local function guid(v)return string.format('00000000-0000-0000-0000-%012x',v)end
local function identity(i)return{InstanceId=R.guid_from_string(guid(i)),PlayerUId=R.guid_from_string(ZERO)}end
local function fixture(m)
 mode=m;files={};queue={};classes={};paths={};counts={};frame=0;clock_now=0;in_game=false
 local base,director,work,concrete,module
 local slots={}
 for i=1,5 do
  local parameter,actor,cp,controller,component,top,root,worker
  parameter=obj('PalIndividualCharacterParameter','P'..i,{
   GetPalId=function()return identity(i)end,GetBaseCampId=function()return R.guid_from_string(BASE)end,GetGroupId=function()return R.guid_from_string(mode=='foreign_worker'and BASE or GUILD)end,
   GetCharacterID=function()return'Lamball'end,GetLevel=function()return 10 end,IsDead=function()return false end,IsSleeping=function()return mode=='sleeping'end,
   GetHungerType=function()return 0 end,GetWorkerSick=function()return 0 end,GetSanityValue=function()return 90 end})
  cp=obj('PalCharacterParameterComponent','CP'..i,{GetIndividualParameter=function()return parameter end,
   IsAssignedToAnyWork=function()return mode=='busy'end,IsAssignedFixed=function()return false end,GetWorkId=function()return R.guid_from_string(mode=='busy'and WORK or ZERO)end})
  actor=obj('PalCharacter','A'..i,{HasAuthority=function()return mode~='no_authority'end,GetCharacterParameterComponent=function()return cp end,GetController=function()return controller end})
  controller=obj('PalAIController','C'..i,{HasAuthority=function()return true end,Pawn=actor})
  component=obj('PalAIActionComponent','Comp'..i,{GetOwner=function()return controller end,ControlledPawn=mode=='wrong_component_pawn'and parameter or actor,
   GetCurrentTopParentAction_BP=function()return top end,GetCompositeRoot=function(_,priority)
    local actual=mode=='priority_one'and 1 or 10;assert(priority==actual,'PRIORITY WAS GUESSED OR OMITTED');counts.priorities=(counts.priorities or 0)+1;return root
   end})
  controller.AIActionComponent=component
  top=obj('PawnAction','Top'..i,{OwnerComponent=component,GetActionPriority=function()return mode=='bad_priority'and 7 or mode=='priority_one'and 1 or 10 end},{['/Script/AIModule.PawnAction']=true})
  worker=obj('PalAIActionCompositeWorker','Worker'..i,{GetOwnerComponent=function()return component end,IsPaused=function()return mode=='paused'end,
   GetCharacterParameter=function()return cp end,GetPawn=function()return actor end,GetChild=function()if mode=='cycle'then return root end;return nil end},
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
end
function FindAllOf(class)
 assert(in_game and classes[class],'unapproved/global AI scan')
 counts[class]=(counts[class]or 0)+1;assert(counts[class]==1,'repeated global scan');return classes[class]
end
function StaticFindObject(path)
 assert(in_game);counts.lookup=(counts.lookup or 0)+1
 if mode=='stale_manager'and frame>=3 then return nil end;return paths[path]
end
function ExecuteWithDelay(ms,fn)assert(ms==50);queue[#queue+1]=fn end
function ExecuteInGameThread(fn)assert(not in_game);in_game=true;fn();in_game=false end
function IsInGameThread()return in_game end
dofile=function(path)if path:match('json.lua$')then return J elseif path:match('readers.lua$')then return R end;error(path)end
debug.getinfo=function()return{source=SOURCE}end
io.open=function(path,m)
 assert(path:find('BridgeLab',1,true)and(m=='ab'or m=='wb'));if m=='wb'then files[path]=''end
 return{write=function(_,s)files[path]=(files[path]or'')..s;return true end,close=function()return true end}
end
os.remove=function(path)files[path]=nil;return true end
os.rename=function(a,b)files[b]=assert(files[a]);files[a]=nil;return true end
os.clock=function()if mode=='time_limit'then clock_now=clock_now+.1 end;return clock_now end
local function run(m)
 fixture(m);probe();assert(next(counts)==nil,'eager native work')
 while #queue>0 do frame=frame+1;assert(frame<=7);table.remove(queue,1)()end
 local r=J.decode(assert(files['D:/PalworldServer-LAN/BridgeLab/rpc/lab-worker-active-preflight.json']))
 assert(r.read_only and r.lab_only and not r.apply_supported and not r.assignment_called and not r.actor_spawn_called and not r.ai_action_created and not r.state_changed)
 return r
end
local n=0;local function test(name,fn)fn();n=n+1;print('PASS '..name)end
test('three workers seven frames exact manager lookup no AI scan',function()
 local r=run('ready');assert(r.ok and r.complete and r.native_queries==3 and r.eligible_pairs==3 and #r.workers==3 and #r.callbacks==7)
 assert(counts.actor_reads==3 and counts.PalBaseCampManager==1 and counts.PalMapObjectManager==1 and counts.lookup>0)
 assert(r.workers[1].ai.active_worker_composite and r.workers[1].ai.priority==10)
end)
test('priority is read from top action rather than fixed enum guess',function()local r=run('priority_one');assert(r.ok and r.eligible_pairs==3 and r.workers[1].ai.priority==1)end)
test('busy sleeping paused and unloaded workers do not reach native query',function()
 for _,m in ipairs({'busy','sleeping','paused','unloaded'})do local r=run(m);assert(r.ok and r.native_queries==0 and #r.workers==3 and not counts.native)end
end)
test('unknown priority cycle wrong ownership and authority fail closed',function()
 for _,m in ipairs({'bad_priority','cycle','wrong_component_pawn','foreign_worker','no_authority','replaced'})do local r=run(m);assert(not r.ok and r.native_queries==0 and not counts.native)end
end)
test('unregistered facility or stale manager stops dependent native work',function()
 for _,m in ipairs({'unregistered','stale_manager'})do local r=run(m);assert(not r.ok and not r.complete and r.native_queries==0)end
end)
test('waiting director and CPU budget stop before worker lookup',function()for _,m in ipairs({'waiting','time_limit'})do local r=run(m);assert(not r.ok and not r.complete and not counts.actor_reads)end end)
test('native unsuitable result remains read-only and ineligible',function()local r=run('unsuitable');assert(r.ok and r.native_queries==3 and r.eligible_pairs==0)end)
test('production path rejects before scheduling or scanning',function()
 fixture('ready');SOURCE='@D:/steam/steamapps/common/PalServer/Pal/Binaries/Win64/ue4ss/Mods/PalLiveBridge/Scripts/probe.lua'
 assert(not pcall(probe)and #queue==0 and next(counts)==nil)
end)
print('OK '..n..' active-worker LOCAL MOCK groups; no native runtime claim')
