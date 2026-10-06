-- Permission is published by the owned runtime only after one normal native
-- world-load observation. Every use compares it with the actual current world
-- and the native client process; a profile boolean cannot grant authority.
local M={version=1}
local function live(o)return o and o:IsValid()and not o:GetFullName():find('Default__',1,true)end
local function text(v)return type(v)=='string'and v or v:ToString()end
local function path(v)return assert(v):gsub('\\','/'):gsub('/+$','')end
function M.new(o)
 local J,P,s=assert(o.json),assert(o.paths),assert(o.scope)
 assert(s.kind=='palcraft_standalone_runtime'and s.mode=='standalone','Owned standalone scope required')
 assert(path(s.install_root_windows)==path(P.root),'Scope belongs to another installation')
 assert(path(s.pal_exe_windows)==path(os.getenv('PALCRAFT_PAL_EXE')),'Trusted actual executable differs')
 assert(path(s.rpc_root_windows)==path(os.getenv('PALCRAFT_RPC_ROOT')),'Trusted actual RPC directory differs')
 local U=StaticFindObject('/Script/Pal.Default__PalUtility')
 local G=StaticFindObject('/Script/Engine.Default__GameplayStatics')
 local S=StaticFindObject('/Script/Engine.Default__KismetSystemLibrary')
 local identify,why=package.loadlib(assert(s.credit_dll_windows),'palcraft_escrow_client_identity_v1');assert(identify,why)
 local permission_path=P.join('.palcraft/standalone/owned-loaded-save-permission.json')
 local identity_path=path(s.rpc_root_windows)..'/escrow-client-process.json'
 local last_identity,process
 local function read(p)
  local f=io.open(p,'rb');if not f then return end
  local bytes=f:read('*a');f:close();return J.decode(bytes)
 end
 local api={}
 function api.process()
  assert(IsInGameThread(),'Actual game thread required')
  local now=os.time()
  if last_identity~=now then
   os.remove(identity_path)
   identify();process=assert(read(identity_path),'Actual native process identity unavailable');last_identity=now
  end
  assert(process.kind=='palworld_client_process_identity'and process.read_only==true and process.native_code_matched==true,
   'Native client process/code gate failed')
  assert(process.executable_sha256==s.executable_sha256 and process.pid>0 and
   type(process.process_created_filetime)=='string'and process.process_created_filetime:match('^%d+$'),
   'Actual executable/process lifecycle differs')
  assert(now-process.observed_unix>=-1 and now-process.observed_unix<=2,'Native process identity stale')
  return process,tostring(process.pid)..':'..process.process_created_filetime
 end
 function api.authorize(observed)
  assert(IsInGameThread(),'Actual game thread required')
  local permission=assert(read(permission_path),'Runtime normal-load ownership observation pending')
  local p,epoch=api.process()
  assert(permission.source=='runtime_owned_normal_load_observation'and permission.process_epoch==epoch,
   'Runtime observation belongs to another actual process')
  assert(observed.world_id==s.world_directory and observed.host_uid==s.pal_uid,
   'Current saved world/host differs from owned restoration')
  local command=text(S:GetCommandLine())
  local user=assert(command:match('%-UserDir="([^"]+)"')or command:match('%-UserDir=([^%s]+)'),
   'Actual private UserDir absent from native command line')
  assert(path(user):lower()==path(s.private_user_dir_windows):lower(),'Actual UserDir differs from owned private save')
  local gi=G:GetGameInstance(observed.pc)
  assert(live(gi)and text(gi:GetSelectedWorldSaveDirectoryName())==observed.world_id,
   'Actual normal world selection differs')
  local manager=U:GetSaveGameManager(observed.pc)
  assert(live(manager)and manager:GetAddress()==observed.save_manager_address and manager:IsLoadedWorldData()==true,
   'Current native save manager differs')
  assert(text(manager.WorldSaveDataLoadFailedDirectoryName)=='','Native world load failed')
  local q=assert(permission.native_context)
  assert(q.world_address==observed.world_address and q.save_manager_address==observed.save_manager_address
   and q.controller_address==observed.pc:GetAddress()and q.game_state_address==observed.game_state:GetAddress()
   and q.world_id==observed.world_id and q.host_uid==observed.host_uid,
   'Runtime observation belongs to another actual loaded context')
  if observed.loaded_save_address then assert(q.loaded_save_address==observed.loaded_save_address,'Loaded save object differs')end
  local save=path(s.private_user_dir_windows)..'/Saved/SaveGames/'..assert(s.steam_save_directory)..'/'..observed.world_id
  assert(path(permission.world_save_root)==save and path(s.installed_level_path_windows)==save..'/Level.sav',
   'Owned normal observation names another save root')
  local f=assert(io.open(save..'/Level.sav','rb'),'Owned installed Level missing');f:close()
  f=assert(io.open(save..'/Players/'..observed.host_uid:gsub('-',''):upper()..'.sav','rb'),'Owned saved native host missing');f:close()
  local sha=permission.observation_record_sha256
  assert(type(sha)=='string'and #sha==64 and sha:match('^%x+$'),'Actual normal observation digest missing')
  return{verified=true,source='runtime_owned_loaded_save',world_id=observed.world_id,
   world_address=observed.world_address,save_manager_address=observed.save_manager_address,
   loaded_world_native=true,loaded_save_address=observed.loaded_save_address,host_uid=observed.host_uid,
   observation_record_sha256=sha,process_epoch=epoch,world_save_root=save}
 end
 return api
end
return M
