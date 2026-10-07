-- Targeted object-contract test only. It does not attest a loaded Pal world or create credentials.
local delta=assert(arg[1],'Public bundle directory required')
local J=dofile(delta..'/checks/deps/json.lua')
local R=dofile(delta..'/checks/deps/readers.lua')
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
function gs:GetWorldSaveDirectoryName()return'ABCDEF0123456789ABCDEF0123456789'end
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
   world_save_root='/owned/contract-only/ABCDEF0123456789ABCDEF0123456789',process_epoch='contract-only-process'}
 end}



local now=1700000000
options.now=function()return now end
local realm=dofile(delta..'/checks/deps/local_realm.lua').new(options)
local service_authority=dofile(delta..'/checks/deps/standalone_authority.lua')
local actual_dofile=dofile
local current_counts,store_rows,pointer
local process={kind='palworld_client_process_identity',native_code_matched=true,read_only=true,
 executable_sha256='e590b5e7bfaa3fea40fab1a02cc72c8fc5fd6f8631ef2308e95ac56c25195837',
 pid=424242,process_created_filetime='133000000000000001',observed_unix=now}
local native_calls,provider_fail=0,false
function IsInGameThread()return true end
function StaticFindObject(path)
 return ({['/Script/Pal.Default__PalUtility']=utility,
  ['/Script/Engine.Default__GameplayStatics']=gameplay,
  ['/Script/Engine.Default__KismetSystemLibrary']=system})[path]
end
local service_env=setmetatable({},{__index=_G})
service_env.dofile=function(path)
 if path:match('/exchange_store.lua$')then
  return {native_commit=function()return function()end end,new=function()
   return {latest=function(prefix)return store_rows[prefix]end,
    append=function(prefix,row)current_counts.wal_append=current_counts.wal_append+1;store_rows[prefix]=row end}
  end}
 elseif path:match('/standalone_authority.lua$')then
  return {read=function(...)
   current_counts.authority_read=current_counts.authority_read+1
   return service_authority.read(...)
  end}
 end
 return actual_dofile(path)
end
service_env.package={loadlib=function()
 current_counts.loadlib=current_counts.loadlib+1
 return function()native_calls=native_calls+1 end
end}
service_env.os={time=function()return now end,getenv=function(key)
 return ({PALCRAFT_EXCHANGE_ROOT='/contract-only/exchange',PALCRAFT_RPC_ROOT='/contract-only/rpc'})[key]
end,remove=function()return true end,rename=function()return true end}
service_env.io={open=function(path,mode)
 if mode=='rb'then
  if path:match('/escrow%-client%-process.json$')then
   current_counts.identity_read=current_counts.identity_read+1
   return {read=function()return J.encode(process)end,close=function()return true end}
  elseif path:match('/escrow%-client%-process%-binding.json$')and pointer then
   return {read=function()return J.encode(pointer)end,close=function()return true end}
  end
  return nil
 end
 assert(path:match('/escrow%-client%-process%-binding.json.tmp$'),'unexpected fixture write')
 return {write=function(_,bytes)pointer=J.decode(bytes);return true end,
  flush=function()return true end,close=function()return true end}
end}
local function load_service(source,injected)
 current_counts={loadlib=0,authority_read=0,identity_read=0,process_provider=0,wal_append=0}
 store_rows={};pointer=nil;native_calls=0
 local service=assert(loadfile(delta..'/'..source..'/server/standalone_service.lua','t',service_env))()
 local o={scope={mode='standalone',world_directory=gs:GetWorldSaveDirectoryName(),pal_uid=uid,
  exchange_root='/contract-only/exchange',rpc_root='/contract-only/rpc'},json=J,readers=R,
  durable_dll='contract-only-durable.dll',credit_dll='contract-only-credit.dll'}
 if injected then
  o.local_realm=realm
  o.process_identity=function()
   current_counts.process_provider=current_counts.process_provider+1
   assert(not provider_fail,'native process verifier fixture rejection')
   return process,'424242:133000000000000001'
  end
 end
 return service.new(o)
end
local cases=J.array();local counts={}
local function test(name,f)f();cases[#cases+1]={name=name,passed=true}end

test('same_callback_verified_realm_and_process_remove_duplicate_scan_and_native_identity_write',function()
 realm:begin_frame();assert(realm:current())
 local service=load_service('source',true);local before=scans
 service.tick();service.tick()
 assert(service.ready and service.binding.world_directory==gs:GetWorldSaveDirectoryName())
 assert(scans==before and native_calls==0 and current_counts.loadlib==0 and current_counts.authority_read==0)
 assert(current_counts.identity_read==0 and current_counts.process_provider==2 and current_counts.wal_append==1)
 counts.injected=current_counts;counts.injected.service_native_identity_calls=native_calls
 counts.injected.service_global_scans=scans-before
 realm:end_frame()
end)

test('injected_realm_UID_or_native_process_failure_rejects_without_independent_fallback',function()
 local service=load_service('source',true)
 permission=false;realm:begin_frame()
 local ok=pcall(service.tick);assert(not ok and not service.ready and current_counts.wal_append==0)
 assert(native_calls==0 and current_counts.authority_read==0 and current_counts.process_provider==0)
 realm:end_frame();permission=true
 realm:begin_frame();assert(realm:current());local saved_d=guid.D;guid.D=saved_d+1
 ok=pcall(service.tick);assert(not ok and not service.ready and current_counts.wal_append==0)
 assert(native_calls==0 and current_counts.authority_read==0 and current_counts.process_provider==0)
 guid.D=saved_d;realm:end_frame()
 provider_fail=true;realm:begin_frame()
 ok=pcall(service.tick);assert(not ok and not service.ready and current_counts.wal_append==0)
 assert(native_calls==0 and current_counts.authority_read==0 and current_counts.identity_read==0)
 realm:end_frame();provider_fail=false
end)

test('uninjected_independent_service_keeps_original_authority_and_native_identity_path',function()
 local baseline=load_service('base',false);local before=scans
 baseline.tick();local binding=baseline.binding
 assert(native_calls==1 and scans-before==2 and current_counts.authority_read==1 and current_counts.identity_read==1)
 local expected=J.encode(binding)
 local service=load_service('source',false);before=scans
 service.tick()
 assert(J.encode(service.binding)==expected and service.ready)
 assert(native_calls==1 and scans-before==2 and current_counts.authority_read==1 and current_counts.identity_read==1)
 counts.independent=current_counts;counts.independent.service_native_identity_calls=native_calls
 counts.independent.service_global_scans=scans-before
end)
print(J.encode({ok=true,targeted_cases=3,cases=cases,counts=counts,original_object_fixture_reused=true,
 actual_installed_game_or_scene_changed=false,actual_fps_or_latency_proven=false,
 native_methods_or_durable_io_executed=false,fixture_only=true}))
