-- Targeted object-contract test only. It does not attest a loaded Pal world or create credentials.
local base=assert(arg[1]);local J=dofile(base..'/../palworld-live/bridge/PalLiveBridge/Scripts/json.lua')
local R=dofile(base..'/../palworld-live/bridge/PalLiveBridge/Scripts/readers.lua')
local dir=assert(arg[2]);local original_dir=assert(arg[3])
local seq=20;local fullname_calls,manager_getters=0,0
local function obj(name,fields)
 fields=fields or{};seq=seq+1;fields.addr=seq;fields.alive=true
 function fields:IsValid()return self.alive end;function fields:GetAddress()return self.addr end
 function fields:GetFullName()fullname_calls=fullname_calls+1;return name end;return fields
end
local world=obj('World /Game/Pal/Maps/MainWorld_5.MainWorld')
local guid={A=0x11111111,B=0x11111111,C=0x11111111,D=0x11111111};local uid=R.guid_to_string(guid):lower()
local localplayer=obj('PalLocalPlayer /Engine/Transient.ContractOnly')
local pc=obj('PalPlayerController /Game/MainWorld.PC',{Player=localplayer})
pc.local_controller=true;pc.authority=true
function pc:IsLocalController()return self.local_controller end;function pc:HasAuthority()return self.authority end
function pc:GetWorld()return world end;function pc:GetPlayerUId()return guid end
local pawn=obj('PalPlayerCharacter /Game/MainWorld.Pawn',{authority=true,initialized=true})
function pawn:HasAuthority()return self.authority end;function pawn:IsInitialized()return self.initialized end
function pawn:GetWorld()return world end;function pawn:GetController()return pc end
pc.Pawn=pawn;function pc:GetDefaultPlayerCharacter()return self.Pawn end
local gs=obj('PalGameStateInGame /Game/MainWorld.GS',{ServerSessionId=''})
function gs:HasAuthority()return true end;function gs:GetWorld()return world end
function gs:GetWorldSaveDirectoryName()return'ContractWorld'end
local individual=obj('PalIndividualHandle Contract');function individual:GetIndividualID()return{PlayerUId=guid}end
function individual:TryGetIndividualActor()return pawn end
local account=obj('PalPlayerAccount Contract',{IndividualHandle=individual})
local tx=obj('PalNetworkTransmitter /Game/MainWorld.Tx');function tx:GetOwner()return pc end;function tx:GetWorld()return world end
local component=obj('PalNetworkTransmitterPlayer Contract');function component:GetOwner()return tx end
function tx:GetPlayer()return component end;pc.Transmitter=tx
local loaded=obj('PalWorldSaveData Contract');local manager=obj('PalSaveGameManager Contract',{loaded=true,WorldSaveDataLoadFailedDirectoryName=''})
function manager:IsLoadedWorldData()return self.loaded end;function manager:GetLoadedWorldSaveData()return loaded end
local objects={PalPlayerController={pc},PalGameStateInGame={gs},PalPlayerAccount={account},PalSaveGameManager={manager}}
local scans,permission_calls,options_calls=0,0,0
function FindAllOf(kind)scans=scans+1;return objects[kind]or{}end
local utility=obj('PalUtility Contract',{mode='Standalone',levels=true})
function utility:GetNetMode()return self.mode end;function utility:IsAllLevelLoaded()return self.levels end
utility.multiplayer=false;function utility:GetOptionWorldSettings()return{bIsMultiplay=self.multiplayer}end
function utility:IsMultiplayer()return self.multiplayer end
local option_subsystem=obj('PalOptionSubsystem Contract');function option_subsystem:GetWorld()return world end
local settings=setmetatable({}, {__index=function(_,k)if k=='bIsMultiplay'then return utility.multiplayer end end})
option_subsystem.OptionWorldSettings=settings
function utility:GetOptionSubsystem()options_calls=options_calls+1;return option_subsystem end
function utility:GetSaveGameManager()manager_getters=manager_getters+1;return manager end
local system=obj('KismetSystemLibrary Contract',{dedicated=false})
function system:IsDedicatedServer()return self.dedicated end;function system:IsStandalone()return utility.mode=='Standalone'end
local gameplay=obj('GameplayStatics Contract');function gameplay:GetGameState()return gs end
local gi=obj('PalGameInstance Contract');function gi:GetSelectedWorldSaveDirectoryName()return gs:GetWorldSaveDirectoryName()end
function gameplay:GetGameInstance()return gi end
local getter_available=true
function gameplay:GetNumPlayerControllers()assert(getter_available,'unsupported fixture getter');return #objects.PalPlayerController end
function gameplay:GetNumLocalPlayerControllers()
 assert(getter_available,'unsupported fixture getter');local n=0
 for _,p in ipairs(objects.PalPlayerController)do if p:IsLocalController()then n=n+1 end end
 return n
end
function gameplay:GetPlayerController(_,index)return index==0 and objects.PalPlayerController[1]or nil end
function utility:GetLocalPlayerController()return objects.PalPlayerController[1]end
local guidlib=obj('KismetGuidLibrary Contract',{count=0})
function guidlib:NewGuid()self.count=self.count+1;return{A=self.count,B=1,C=1,D=1}end
local permission=true
local options={readers=R,game_thread=function()return true end,utility=utility,guid_library=guidlib,system_library=system,gameplay_statics=gameplay,
 authorize_world_save=function(c)
  permission_calls=permission_calls+1
  if not permission then return nil end
  return{verified=true,source='runtime_owned_loaded_save',world_id=c.world_id,host_uid=c.host_uid,
   world_address=c.world_address,loaded_save_address=c.loaded_save_address,
   save_manager_address=c.save_manager_address,loaded_world_native=true,observation_record_sha256=string.rep('a',64),
   world_save_root='/owned/contract-only/ContractWorld',process_epoch='contract-only-process'}
 end}




-- Only three new bounded cases; reuse the original native-object fixture.
local Realm=dofile(dir..'/base/client/runtime/local_realm.lua')
local cases=J.array();local counts={}
local function test(name,f)f();cases[#cases+1]={name=name,passed=true}end
local function prepared(source,realm,o)
 o=o or{};local queued,writes={},{}
 local paths={journal='/fixture/journal/',bridge='/fixture/bridge/'}
 function paths.role()return o.network and'server'or'client'end
 local target=(o.network and paths.journal or paths.bridge)..'palcraft-collision-status.json'
 local env=setmetatable({},{__index=_G});env._G=env
 if realm then env.PalCraftStandaloneBootstrap={local_realm=realm}end
 local mockio={};for k,v in pairs(io)do mockio[k]=v end
 function mockio.open(path,mode)
  if path==target and mode=='wb'then
   return{write=function(_,value)
    if o.fail_write then error('fixture-status-write-error')end
    writes[#writes+1]=J.decode(value)
   end,close=function()return true end}
  end
  return nil -- No event, setting, asset or production file access.
 end
 env.io=mockio
 function env.dofile(path)
  if path:match('runtime/paths.lua$')then return paths end
  if path:match('json.lua$')then return J end
  if path:match('world_compat.lua$')then
   return{new=function()return{session='fixture-only',status=function()return{fixture=true}end}end}
  end
  error('Unexpected module load: '..path)
 end
 function env.ExecuteInGameThreadWithDelay(delay,fn)queued[#queued+1]={delay=delay,fn=fn}end
 function env.IsInGameThread()return true end
 local m=assert(loadfile(source,'t',env))();m.cleaned=true;m.visual_pipeline_checked=true
 m.install_consumer{
  filter_legacy=function()return true end,on_row=function()return true end,
  block_render_entry=function()return true end,stop=function()end,
  tick=function()
   for _=1,3 do assert(m.context()==gs)end
   if o.fail_body then error('fixture-owned-body-error')end
  end,
  status=function()for _=1,2 do assert(m.context()==gs)end;return{fixture=true}end
 }
 m.set_world_observer({tick=function()for _=1,2 do assert(m.context()==gs)end end},'fixture')
 local function run()
  local row=assert(table.remove(queued,1));row.fn();return row.delay
 end
 return m,run,queued,writes
end
local old=dir..'/base/client/palcraft-collisions.lua'
local new=dir..'/source/client/palcraft-collisions.lua'
local function closed(r)assert(pcall(r.begin_frame,r),'Callback leaked realm frame');r:end_frame()end

test('one_fresh_complete_proof_per_callback_including_status_no_cross_callback_cache',function()
 local r=Realm.new(options);local m,run,queue=prepared(old,r)
 local s,p=scans,permission_calls;assert(run()==500)
 counts.baseline={scans=scans-s,permission=permission_calls-p}
 assert(counts.baseline.scans==40 and counts.baseline.permission==8)
 r=Realm.new(options);m,run,queue=prepared(new,r)
 s,p=scans,permission_calls;assert(run()==500);assert(queue[1].delay==50)
 counts.candidate_initial={scans=scans-s,permission=permission_calls-p}
 assert(scans-s==5 and permission_calls-p==1);closed(r)
 s,p=scans,permission_calls;assert(run()==50)
 counts.candidate_next={scans=scans-s,permission=permission_calls-p}
 assert(scans-s==0 and permission_calls-p==1);closed(r)
 -- A new callback must call the same original permission verifier again.
 permission=false;p=permission_calls;run()
 assert(m.running==false and permission_calls==p+1);closed(r);permission=true
 s,p=scans,permission_calls;assert(r:current());assert(scans-s==5 and permission_calls-p==1)
end)

test('early_abandon_body_error_and_status_error_always_close_only_acquired_scope',function()
 local r=Realm.new(options);local m,run=prepared(new,r);run();closed(r)
 pawn.initialized=false;run();assert(m.abandoned==true and m.running==false);closed(r);pawn.initialized=true
 r=Realm.new(options);m,run=prepared(new,r,{fail_body=true});run()
 assert(m.running==false and m.error:find('fixture-owned-body-error',1,true));closed(r)
 r=Realm.new(options);m,run=prepared(new,r,{fail_write=true})
 local ok,why=pcall(run);assert(not ok and tostring(why):find('fixture-status-write-error',1,true));closed(r)
 assert(m.running==true) -- Original write failure propagates, not relabelled a body error.
end)

test('nested_existing_main_scope_not_closed_and_network_original_trace_unchanged',function()
 local r=Realm.new(options);r:begin_frame();local proof=assert(r:current());local p=permission_calls
 local m,run=prepared(new,r);run()
 assert(m.running==false and m.error:find('One original game-thread frame required',1,true))
 assert(r:current()==proof and permission_calls==p) -- Existing main frame still belongs to its caller.
 r:end_frame();closed(r)
 objects.GameStateBase={gs}
 local function trace(source)
  local seq={};local previous=FindAllOf
  FindAllOf=function(kind)seq[#seq+1]=kind;return previous(kind)end
  local n,call,queue,writes=prepared(source,nil,{network=true});assert(call()==500)
  FindAllOf=previous
  assert(n.running==true and queue[1].delay==50 and writes[1].side=='server')
  return table.concat(seq,','),#writes
 end
 local a,n=trace(old);local b,k=trace(new);assert(a==b and n==k)
end)
print(J.encode{ok=true,targeted_cases=#cases,cases=cases,counts=counts,
 exact_original_collision_module_loaded=true,exact_realm_source_unchanged=true,
 synthetic_only=true,actual_game_or_saved_or_probe=false,
 FPS60_or_night15_performance_accepted=false})
