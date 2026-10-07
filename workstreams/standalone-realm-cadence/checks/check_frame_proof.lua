-- Targeted object-contract test only. It does not attest a loaded Pal world or create credentials.
local base=assert(arg[1]);local J=dofile(base..'/../palworld-live/bridge/PalLiveBridge/Scripts/json.lua')
local R=dofile(base..'/../palworld-live/bridge/PalLiveBridge/Scripts/readers.lua')
local dir=assert(arg[2]);local original_dir=assert(arg[3])
local seq=20
local function obj(name,fields)
 fields=fields or{};seq=seq+1;fields.addr=seq;fields.alive=true
 function fields:IsValid()return self.alive end;function fields:GetAddress()return self.addr end
 function fields:GetFullName()return name end;return fields
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
local scans,permission_calls=0,0
function FindAllOf(kind)scans=scans+1;return objects[kind]or{}end
local utility=obj('PalUtility Contract',{mode='Standalone',levels=true})
function utility:GetNetMode()return self.mode end;function utility:IsAllLevelLoaded()return self.levels end
utility.multiplayer=false;function utility:GetOptionWorldSettings()return{bIsMultiplay=self.multiplayer}end
function utility:IsMultiplayer()return self.multiplayer end
local option_subsystem=obj('PalOptionSubsystem Contract');function option_subsystem:GetWorld()return world end
local settings=setmetatable({}, {__index=function(_,k)if k=='bIsMultiplay'then return utility.multiplayer end end})
option_subsystem.OptionWorldSettings=settings
function utility:GetOptionSubsystem()return option_subsystem end
function utility:GetSaveGameManager()return manager end
local system=obj('KismetSystemLibrary Contract',{dedicated=false})
function system:IsDedicatedServer()return self.dedicated end;function system:IsStandalone()return utility.mode=='Standalone'end
local gameplay=obj('GameplayStatics Contract');function gameplay:GetGameState()return gs end
local gi=obj('PalGameInstance Contract');function gi:GetSelectedWorldSaveDirectoryName()return gs:GetWorldSaveDirectoryName()end
function gameplay:GetGameInstance()return gi end
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

local baseline=dofile(original_dir..'/client/runtime/local_realm.lua').new(options)
local before_scans,before_permission=scans,permission_calls
for _=1,20 do local p=assert(baseline:current());assert(baseline:validate(p,pc));assert(baseline:same_world(tx,p));baseline:status()end
local old_scans,old_permission=scans-before_scans,permission_calls-before_permission
assert(old_scans==400 and old_permission==80)
local realm=dofile(dir..'/client/runtime/local_realm.lua').new(options)
local cases=J.array()
local function test(name,f)f();cases[#cases+1]={name=name,passed=true}end
local last_proof
local function frame_work()
 for _=1,20 do local p=assert(realm:current());assert(realm:validate(p,pc));assert(realm:same_world(tx,p));realm:status();last_proof=p end
end
test('one_initial_full_discovery_and_permission_shared_only_inside_original_frame',function()
 local s,p=scans,permission_calls;realm:begin_frame();frame_work();realm:end_frame()
 assert(scans-s==5 and permission_calls-p==1)
end)
test('next_frame_one_controller_discovery_and_original_permission_revalidation',function()
 local s,p=scans,permission_calls;realm:begin_frame();frame_work();realm:end_frame()
 assert(scans-s==1 and permission_calls-p==1)
end)
test('each_operation_live_possession_and_loaded_context_change_force_original_full_recheck',function()
 realm:begin_frame();local p=assert(realm:current());local s=scans
 pawn.initialized=false;assert(realm:validate(p,pc)==false and scans-s==2) -- original sampler rejects after the two controller scans
 realm:end_frame();pawn.initialized=true
 realm:begin_frame();p=assert(realm:current());s=scans
 loaded.alive=false;local q=assert(realm:current());assert(q.loaded_save==nil and scans-s==5)
 realm:end_frame();loaded.alive=true
 realm:begin_frame();assert(realm:current());realm:end_frame()
end)
test('next_frame_permission_failure_is_not_cached_authority_and_frame_error_is_fail_closed',function()
 permission=false;local s,p=scans,permission_calls;realm:begin_frame()
 assert(realm:current()==nil and scans-s==1 and permission_calls-p==1)
 for _=1,20 do assert(realm:current()==nil)end
 assert(scans-s==1 and permission_calls-p==1)
 realm:end_frame();permission=true
 realm:begin_frame();assert(realm:current());realm:end_frame()
end)
test('fresh_controller_uniqueness_and_remote_peer_preserved_each_frame',function()
 local remote=obj('PalPlayerController Remote',{NetConnection=obj('ActualRemoteConnection Contract')})
 function remote:IsLocalController()return false end;function remote:GetWorld()return world end
 objects.PalPlayerController={pc,remote};realm:begin_frame();assert(realm:current()==nil);realm:end_frame()
 objects.PalPlayerController={pc};realm:begin_frame();assert(realm:current());realm:end_frame()
end)
test('explicit_invalidate_and_world_mode_change_never_relabel_old_proof',function()
 realm:begin_frame();local p=assert(realm:current());realm:invalidate('normal_title')
 local q=assert(realm:current());assert(q.server_session_id~=p.server_session_id and realm:validate(p,pc)==false)
 realm:end_frame();utility.multiplayer=true
 realm:begin_frame();assert(realm:current()==nil);realm:end_frame();utility.multiplayer=false
end)
test('frame_cleanup_and_outside_frame_preserve_original_full_sampler',function()
 realm:begin_frame();assert(realm:current());realm:end_frame()
 local s,p=scans,permission_calls;assert(realm:current());assert(scans-s==5 and permission_calls-p==1)
end)
print(J.encode{ok=true,targeted_cases=#cases,cases=cases,
 original_fixture_reused=true,baseline_identical_work={global_FindAllOf=old_scans,permission_calls=old_permission},
 candidate_initial_frame={global_FindAllOf=5,permission_calls=1},candidate_stable_frame={global_FindAllOf=1,permission_calls=1},
 actual_loaded_game=false,actual_fps_or_input_camera_latency_proven=false,new_probes_or_credentials=false})
