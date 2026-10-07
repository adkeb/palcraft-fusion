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
function utility:GetSaveGameManager()return manager end
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


local baseline=dofile(original_dir..'/client/runtime/local_realm.lua').new(options)
local realm=dofile(dir..'/client/runtime/local_realm.lua').new(options)
local cases=J.array()
local function test(name,f)f();cases[#cases+1]={name=name,passed=true}end
local function work(api)
 for _=1,20 do local p=assert(api:current());assert(api:validate(p,pc));assert(api:same_world(tx,p));api:status()end
end
local old_scans,old_options,old_permission,new_scans,new_options,new_permission
test('actual_single_controller_native_path_avoids_globals_and_full_rechecks_sameframe',function()
 baseline:begin_frame();work(baseline);baseline:end_frame()
 local s,v,p=scans,options_calls,permission_calls
 baseline:begin_frame();work(baseline);baseline:end_frame()
 old_scans,old_options,old_permission=scans-s,options_calls-v,permission_calls-p
 realm:begin_frame();work(realm);realm:end_frame()
 s,v,p=scans,options_calls,permission_calls
 realm:begin_frame();work(realm);realm:end_frame()
 new_scans,new_options,new_permission=scans-s,options_calls-v,permission_calls-p
 assert(old_scans==1 and old_options==80 and old_permission==1)
 assert(new_scans==0 and new_options==1 and new_permission==1)
end)
test('sameframe_possession_change_and_nextframe_permission_failure_reject_then_revalidate',function()
 realm:begin_frame();local p=assert(realm:current());local s=scans
 pawn.initialized=false;assert(realm:validate(p,pc)==false and scans-s==2)
 realm:end_frame();pawn.initialized=true
 realm:begin_frame();assert(realm:current());realm:end_frame()
 permission=false;realm:begin_frame();assert(realm:current()==nil);realm:end_frame();permission=true
 realm:begin_frame();assert(realm:current());realm:end_frame()
end)
test('unsupported_getter_and_remote_population_keep_original_global_and_scope_rejection',function()
 getter_available=false;local s=scans;realm:begin_frame();assert(realm:current());realm:end_frame()
 assert(scans-s==1);getter_available=true
 local remote=obj('PalPlayerController Remote',{NetConnection=obj('RemoteConnection Contract')})
 function remote:IsLocalController()return false end;function remote:GetWorld()return world end
 objects.PalPlayerController={pc,remote};realm:begin_frame();assert(realm:current()==nil);realm:end_frame()
 objects.PalPlayerController={pc};realm:begin_frame();assert(realm:current());realm:end_frame()
end)
print(J.encode{ok=true,targeted_cases=#cases,cases=cases,original_object_fixture_reused=true,
 inherited13_stable_work={FindAllOf=old_scans,GetOptionSubsystem=old_options,permission_calls=old_permission},
 candidate14_stable_work={FindAllOf=new_scans,GetOptionSubsystem=new_options,permission_calls=new_permission},
 actual_root_game_run=false,actual_FPS_camera_or_control_improvement_proven=false,new_probes_or_credentials=false})
