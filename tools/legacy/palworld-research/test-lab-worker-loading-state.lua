-- Local mock only; native Lab acceptance remains separate.
local J=dofile('work/palworld-live/bridge/PalLiveBridge/Scripts/json.lua')
local R=dofile('work/palworld-live/bridge/PalLiveBridge/Scripts/readers.lua')
local probe=assert(loadfile('work/palworld-live/lab/lab-worker-loading-state.lua'))
local BASE='00000000-0000-4000-8000-000000000031';local GUILD='00000000-0000-4000-8000-00000000001b'
local source='@D:/PalworldServer-LAN/BridgeLab/Pal/Binaries/Win64/ue4ss/Mods/PalLiveBridge/Scripts/lab-worker-loading-state.lua'
local files,queue,classes,counts,mode,frame,clock_now,in_game
local function obj(name,p)
 p.IsValid=function()return true end;p.GetFullName=function()return name end
 return setmetatable(p,{__index=function(_,k)error('unexpected access '..name..'.'..k)end})
end
local function fixture(m)
 mode=m;files={};queue={};counts={};frame=0;clock_now=0;in_game=false
 local base
 local director=obj('Director',{BaseCampId=R.guid_from_string(BASE),GetOuter=function()if mode=='wrong_owner'then return nil end;return base end,
  State=mode=='active'and 2 or 1,bEnableWorkerPlayerTracking=true,bIsRaidBossAreaShuttingDown=false})
 local collection=obj('Collection',{GetOuter=function()return base end})
 base=obj('Base',{GetId=function()return R.guid_from_string(BASE)end,
  GetGroupIdBelongTo=function()return R.guid_from_string(mode=='foreign_guild'and BASE or GUILD)end,
  IsAvailable=function()return true end,CurrentState=1,WorkerDirector=director,MapObjectCollection=collection,
  SignificanceInfo={DistanceInRangeFromPlayer=15000,TickInterval=1,bMergeDropItems=true,bUpdateSimple=true}})
 local bm=obj('BaseManager',{TryGetModel=function(_,g,out)
  if R.guid_to_string(g)~=BASE or mode=='base_absent'then return false end;out.OutModel=base;return true
 end})
 local owner=obj('BP_PalGameStateInGame_C',{HasAuthority=function()return mode~='no_authority'end})
 local init=obj('InitManager',{GetOwner=function()return owner end,bCanReferToWorldObject=true,CurrentSequenceIndex=7})
 classes={PalBaseCampManager={bm},PalGameSystemInitManagerComponent={init}}
 if mode=='manager_limit'then classes.PalBaseCampManager={bm,bm,bm,bm,bm}end
end
function FindAllOf(class)
 assert(in_game and classes[class],'unexpected scan or off-thread')
 counts[class]=(counts[class]or 0)+1;counts[frame]=(counts[frame]or 0)+1;assert(counts[frame]==1,'multiple scans within callback')
 return classes[class]
end
function ExecuteWithDelay(ms,fn)assert(ms==50);queue[#queue+1]=fn end
function ExecuteInGameThread(fn)assert(not in_game);in_game=true;fn();in_game=false end
function IsInGameThread()return in_game end
dofile=function(path)if path:match('json.lua$')then return J elseif path:match('readers.lua$')then return R end;error(path)end
debug.getinfo=function()return{source=source}end
io.open=function(path,m)
 assert(path:find('BridgeLab',1,true)and(m=='ab'or m=='wb'),'unexpected I/O')
 if m=='wb'then files[path]=''end
 return{write=function(_,s)files[path]=(files[path]or'')..s;return true end,close=function()return true end}
end
os.remove=function(path)files[path]=nil;return true end
os.rename=function(a,b)files[b]=assert(files[a]);files[a]=nil;return true end
os.clock=function()if mode=='time_limit'then clock_now=clock_now+.1 end;return clock_now end
local function run(m)
 fixture(m);probe();assert(next(counts)==nil)
 while #queue>0 do frame=frame+1;assert(frame<=4);table.remove(queue,1)()end
 local r=J.decode(assert(files['D:/PalworldServer-LAN/BridgeLab/rpc/lab-worker-loading-state.json']))
 assert(r.read_only and r.lab_only and not r.apply_supported and not r.actor_activation_called and not r.loading_request_called and not r.assignment_called and not r.state_changed)
 return r
end
local n=0;local function test(name,fn)fn();n=n+1;print('PASS '..name)end
test('one global then one registered base per frame; waiting state and unknown native readiness explicit',function()
 local r=run('ready');assert(r.ok and r.complete and #r.callbacks==4 and #r.bases==3)
 assert(r.bases[1].director.state_name=='WaitForLoadingAround'and r.bases[1].registration_verified)
 assert(r.bases[1].significance.simple_update and r.global_init.can_refer_to_world_object)
 assert(not r.bases[2].registered_available and not r.bases[3].registered_available)
 assert(r.bases[1].world_partition_loading_complete:find('unknown',1,true))
end)
test('active director does not claim worker activation',function()local r=run('active');assert(r.ok and r.bases[1].blocker=='director_active_does_not_prove_worker_actor_loaded')end)
test('unregistered bases stop before dependent field reads',function()local r=run('base_absent');assert(r.ok and #r.bases==3 and not r.bases[1].director)end)
test('guild and director outer mismatch fail closed',function()for _,m in ipairs({'foreign_guild','wrong_owner'})do local r=run(m);assert(not r.ok and not r.complete and #r.errors==1)end end)
test('authority manager and CPU limits reject',function()for _,m in ipairs({'no_authority','manager_limit','time_limit'})do local r=run(m);assert(not r.ok and not r.complete)end end)
test('production path fails before scheduling or native reads',function()
 fixture('ready');source='@D:/steam/steamapps/common/PalServer/Pal/Binaries/Win64/ue4ss/Mods/PalLiveBridge/Scripts/test.lua'
 assert(not pcall(probe)and #queue==0 and next(counts)==nil)
end)
print('OK '..n..' loading-state LOCAL MOCK groups; no native-runtime claim')
