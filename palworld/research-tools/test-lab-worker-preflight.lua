-- Local mock acceptance only. This cannot prove native runtime safety or assignment support.
local real_dofile=dofile
local J=real_dofile('work/palworld-live/bridge/PalLiveBridge/Scripts/json.lua')
local RealR=real_dofile('work/palworld-live/bridge/PalLiveBridge/Scripts/readers.lua')
local function propguid(s)return RealR.guid_from_string(s)end
local PROBE='work/palworld-live/lab/lab-worker-preflight.lua'
local probe=assert(loadfile(PROBE))
local BASE='00000000-0000-4000-8000-000000000031';local GUILD='00000000-0000-4000-8000-00000000001b'
local ZERO='00000000-0000-0000-0000-000000000000'
local function guid(n)return string.format('00000000-0000-0000-0000-%012x',n)end
local IID,MID,CID,WID,UID=guid(1),guid(2),guid(3),guid(4),guid(5)
local SOURCE='@D:/PalworldServer-LAN/BridgeLab/Pal/Binaries/Win64/ue4ss/Mods/PalLiveBridge/Scripts/lab-worker-preflight.lua'
local files,classes,counts,mode,registered,clock_now
local function object(name,fields)
 local o=fields or{};o.IsValid=function()return true end;o.GetFullName=function()return name end
 return setmetatable(o,{__index=function(_,key)error('UNEXPECTED METHOD OR PROPERTY: '..name..'.'..key)end})
end
local function iid()return{InstanceId=IID,PlayerUId=ZERO}end
local function array_slot(s)return{get=function()return s end}end
local function fixture(m)
 mode=m;files={};classes={};counts={};registered=false;clock_now=0
 local base,director,handle,cp,action,concrete,module,work,actor
 local p=object('parameter',{
 GetPalId=iid,GetBaseCampId=function()return mode=='membership_zero'and ZERO or BASE end,GetGroupId=function()return GUILD end,
 GetCharacterID=function()return'Lamball'end,GetLevel=function()return 10 end,IsDead=function()return false end,IsSleeping=function()return mode=='sleeping'end,
 GetHungerType=function()return 0 end,GetWorkerSick=function()return 0 end,GetSanityValue=function()return 90 end,
 GetWorkSuitabilityRankWithCharacterRank=function(_,n)return n==5 and 1 or 0 end})
 cp=object('cp',{GetIndividualParameter=function()return p end,IsAssignedToAnyWork=function()return mode=='busy'end,IsAssignedFixed=function()return false end,GetWorkId=function()return mode=='busy'and WID or ZERO end})
 actor=object('actor',{HasAuthority=function()return true end,GetCharacterParameterComponent=function()return cp end})
 handle=object('handle',{GetIndividualID=iid,TryGetIndividualParameter=function()return p end,TryGetIndividualActor=function()if mode=='unloaded'then return nil end;return actor end})
 local slot=object('slot',{GetSlotIndex=function()return 0 end,IsEmpty=function()return false end,GetHandle=function()return handle end})
 director=object('director',{BaseCampId=propguid(BASE),GetOuter=function()return base end,GetCharacterHandleSlots=function(_,out)out[1]=array_slot(slot)end})
 base=object('base',{GetId=function()return BASE end,GetGroupIdBelongTo=function()return mode=='foreign_guild'and guid(88)or GUILD end,IsAvailable=function()return true end,WorkerDirector=director})
 local function guarded(value)return function()assert(registered,'NATIVE CONCRETE GETTER BEFORE REGISTRATION');return value()end end
 concrete=object('concrete',{ModelInstanceId=MID,InstanceId=CID,bDisposed=mode=='disposed',
 GetModelInstanceId=function()counts.identity_reads=(counts.identity_reads or 0)+1;return MID end,GetInstanceId=guarded(function()return CID end),GetBaseCampIdBelongTo=guarded(function()return BASE end),GetBaseCampModelBelongTo=guarded(function()return base end),GetWorkeeModule=guarded(function()return module end)})
 work=object('work',{BaseCampIdBelongTo=propguid(BASE),OwnerMapObjectModelId=propguid(MID),OwnerMapObjectConcreteModelId=propguid(mode=='wrong_owner'and guid(99)or CID),
 GetWorkId=function()return WID end,GetAssignableFixedType=function()return mode=='free_only'and 1 or 0 end,GetWorkName=function()return'Work bench'end,
 GetAssignedCharacters=function(_,out)assert(registered)end,
 IsExistAssignableSlot=function(_,h,fixed)assert(h==handle and fixed==true);counts.query=(counts.query or 0)+1;return mode~='unsuitable'end})
 module=object('module',{TargetWork=work,GetOuter=function()return concrete end,GetWork=function()return work end})
 local model=object('model',{BuildObjectId='CraftingTable',GetConcreteModel=function(_,force)assert(force==false and registered);return concrete end})
 local bm=object('base manager',{TryGetModel=function(_,id,out)if id==BASE then out.OutModel=base;return true end;return false end})
 local mm=object('map manager',{FindModel=function(_,id)assert(id==MID);counts.findmodel=(counts.findmodel or 0)+1;if mode=='unregistered'then return nil end;registered=true;return model end})
 local top=object('top action',{GetActionPriority=function()return mode=='bad_priority'and 7 or 10 end})
 local owner=object('AI owner',{GetCurrentTopParentAction_BP=function()return top end,GetCompositeRoot=function(_,priority)assert(priority==10,'MISSING OR INCORRECT PRIORITY');counts.root=(counts.root or 0)+1;return action end})
 action=object('worker action',{GetCharacterParameter=function()return cp end,IsPaused=function()return false end,GetOwnerComponent=function()return owner end})
 local pc,state,tx
 local guild=object('guild',{GetId=function()return GUILD end,HasGuildPermission=function(_,uid,p)assert(uid==UID and p==7);return true end})
 state=object('state',{GetPlayerController=function()return pc end,GuildBelongTo=guild})
 tx=object('tx',{GetOwner=function()return pc end})
 pc=object('pc',{HasAuthority=function()return true end,IsPlayerController=function()return true end,NetConnection=object('connection'),GetPalPlayerState=function()return state end,GetPlayerUId=function()return UID end,Transmitter=tx})
 classes.PalBaseCampManager={bm};classes.PalMapObjectManager={mm};classes.PalMapObjectWorkeeModule={module};classes.PalAIActionCompositeWorker={action};classes.PalPlayerController={pc}
 if mode=='workee_limit'then classes.PalMapObjectWorkeeModule={};for i=1,1025 do classes.PalMapObjectWorkeeModule[i]=module end end
end
function FindAllOf(class)assert(classes[class],'unexpected global scan '..class);counts[class]=(counts[class]or 0)+1;assert(counts[class]==1,'repeated scan');return classes[class]end
function IsInGameThread()return mode~='wrong_thread'end
function ExecuteWithDelay(_,fn)fn()end
function ExecuteInGameThread(fn)fn()end
local R={guid_to_string=function(v)if type(v)=='table'then return RealR.guid_to_string(v)end;assert(type(v)=='string');return v end,guid_from_string=function(v)assert(type(v)=='string'and#v==36);return v end}
dofile=function(path)if path:match('json.lua$')then return J elseif path:match('readers.lua$')then return R end error(path)end
debug.getinfo=function()return{source=SOURCE}end
io.open=function(path,openmode)assert(path:find('BridgeLab',1,true));assert(openmode=='wb'or openmode=='ab');if openmode=='wb'then files[path]=''end;return{write=function(_,s)files[path]=(files[path]or'')..s;return true end,close=function()return true end}end
os.remove=function(path)files[path]=nil;return true end
os.rename=function(from,to)files[to]=assert(files[from]);files[from]=nil;return true end
os.clock=function()if mode=='time_limit'then clock_now=clock_now+.03 end;return clock_now end
local function run(mode)
 fixture(mode);probe();local r=J.decode(assert(files['D:/PalworldServer-LAN/BridgeLab/rpc/lab-worker-preflight.json']))
 assert(r.read_only and r.lab_only and not r.apply_supported and not r.native_assignment_called)
 return r
end
local n=0
local function test(name,fn)fn();n=n+1;print('PASS '..name)end
test('ready candidate uses registered model and actual action priority, only reads',function()
 local r=run('ready');assert(r.ok and r.complete and r.counts.eligible_pairs==1 and counts.query==1 and counts.root==1)
 assert(r.bases[1].works[1].registration_verified and r.players[1].guild_permission_7)
end)
test('unregistered concrete only permits the own-GUID copy, never model-dependent getters',function()local r=run('unregistered');assert(r.ok and r.unregistered_modules_skipped==1 and r.counts.works==0 and not counts.query)end)
test('disposed module skipped before model lookup',function()local r=run('disposed');assert(r.ok and r.disposed_modules_skipped==1 and not counts.findmodel and not counts.query)end)
test('work owner mismatch rejects',function()local r=run('wrong_owner');assert(not r.ok and r.counts.works==0 and not counts.query)end)
test('no loaded actor gives no AI scan or suitability query',function()local r=run('unloaded');assert(r.ok and r.counts.loaded_actors==0 and not counts.PalAIActionCompositeWorker and not counts.query)end)
test('zero parameter membership rejects candidates',function()local r=run('membership_zero');assert(r.ok and r.counts.eligible_pairs==0 and not counts.query)end)
test('busy and sleeping workers are retained',function()for _,mode in ipairs({'busy','sleeping'})do local r=run(mode);assert(r.ok and r.counts.eligible_pairs==0 and not counts.query)end end)
test('non-fixed facility and negative native query cannot become eligible',function()local r=run('free_only');assert(r.ok and not counts.query);r=run('unsuitable');assert(r.ok and counts.query==1 and r.counts.eligible_pairs==0)end)
test('foreign guild fails before director worker reads',function()local r=run('foreign_guild');assert(not r.ok and r.counts.workers==0 and r.counts.works==0)end)
test('unknown AI priority fails closed',function()local r=run('bad_priority');assert(not r.ok and not counts.root and not counts.query)end)
test('workee object and CPU limits abort with partial report',function()local r=run('workee_limit');assert(not r.ok and not r.complete and not counts.query);r=run('time_limit');assert(not r.ok and not r.complete and not counts.query)end)
test('production path and wrong game thread are rejected',function()
 fixture('ready');SOURCE='@D:/steam/steamapps/common/PalServer/Pal/Binaries/Win64/ue4ss/Mods/PalLiveBridge/Scripts/probe.lua';assert(not pcall(probe));assert(next(counts)==nil)
 SOURCE='@D:/PalworldServer-LAN/BridgeLab/Pal/Binaries/Win64/ue4ss/Mods/PalLiveBridge/Scripts/lab-worker-preflight.lua'
 local r=run('wrong_thread');assert(not r.ok and not r.complete and next(counts)==nil)
end)
print('OK '..n..' LOCAL MOCK checks; no native-runtime claim')
