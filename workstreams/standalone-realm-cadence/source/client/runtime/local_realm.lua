-- One actual standalone authority context. No transport, credential or synthetic ready state.
local M={version=1}
local ZERO='00000000-0000-0000-0000-000000000000'
local function live(o)return o and o:IsValid()and not o:GetFullName():find('Default__',1,true)end
local function text(v)return type(v)=='string'and v or v:ToString()end
local function address(o)assert(live(o),'Live native object required');return o:GetAddress()end
local function same(a,b)return live(a)and live(b)and address(a)==address(b)end
local function root(p)
 assert(type(p)=='string'and#p>0,'Actual owned world save root required')
 p=p:gsub('\\','/'):gsub('/+$','')
 assert(p:match('^%a:/')or p:sub(1,1)=='/','World save root must be absolute')
 assert(not p:find('%z')and not p:find('[\r\n]'),'World save root invalid')
 for part in p:gmatch('[^/]+')do assert(part~='.'and part~='..','World save root traversal rejected')end
 return p
end
function M.new(o)
 o=assert(o);local R=assert(o.readers);local authorize=assert(o.authorize_world_save,'Owned loaded-save permission verifier required')
 local thread=o.game_thread or IsInGameThread;local now=o.now or os.time
 local utility=o.utility or StaticFindObject('/Script/Pal.Default__PalUtility')
 local guidlib=o.guid_library or StaticFindObject('/Script/Engine.Default__KismetGuidLibrary')
 local system=o.system_library or StaticFindObject('/Script/Engine.Default__KismetSystemLibrary')
 local gameplay=o.gameplay_statics or StaticFindObject('/Script/Engine.Default__GameplayStatics')
 assert(utility and utility:IsValid()and guidlib and guidlib:IsValid()and system and system:IsValid()and gameplay and gameplay:IsValid(),'Actual native utility libraries required')
 local api={generation=0,last_error=nil};local current,key;local traced={}
 local in_frame,frame_proof,frame_error=false,nil,nil
 local function trace(world,step)
  local k=tostring(world:GetAddress())..':'..step
  if not traced[k]then traced[k]=true;print('[PalCraft Standalone] native gate '..step..'\n')end
 end
 local function guid(g)return R.guid_to_string({A=g.A,B=g.B,C=g.C,D=g.D}):lower()end
 local function objects(kind)
  local out={};for _,value in ipairs(FindAllOf(kind)or{})do if live(value)then out[#out+1]=value end end;return out
 end
 local function verify_owned(observed)
  local world,gs,pc,manager=observed.world,observed.game_state,observed.pc,observed.save_manager
  local world_id,uid,loaded=observed.world_id,observed.host_uid,observed.loaded_save
  -- Runtime must verify the selected owned root against this actual loaded save and process.
  trace(world,'runtime-owned-permission');local permission=assert(authorize(observed),'Owned world save permission unavailable')
  assert(permission.verified==true and permission.source=='runtime_owned_loaded_save','Loaded save ownership not verified')
  assert(permission.world_id==world_id and permission.world_address==observed.world_address
   and permission.save_manager_address==observed.save_manager_address and permission.loaded_world_native==true
   and permission.host_uid==uid,'Owned save proof belongs to another context')
  if loaded then assert(permission.loaded_save_address==observed.loaded_save_address,'Loaded save object proof differs')end
  assert(type(permission.observation_record_sha256)=='string'and permission.observation_record_sha256:match('^%x+$')
   and#permission.observation_record_sha256==64,'Actual normal load/selected-root observation record required')
  assert(type(permission.process_epoch)=='string'and#permission.process_epoch>0,'Actual owned process lifecycle required')
  local save_root=root(permission.world_save_root)
  assert(save_root:match('([^/]+)$')==world_id,'Owned save root does not name the actual world')
  observed.world_save_root=save_root;observed.process_epoch=permission.process_epoch
  return observed,table.concat({tostring(address(world)),tostring(address(gs)),tostring(address(pc)),
   tostring(address(manager)),uid,world_id,save_root,permission.process_epoch},'\n')
 end
 local function sample()
  assert(type(thread)=='function'and thread()==true,'Standalone context requires game thread')
  local pc
  for _,candidate in ipairs(objects('PalPlayerController'))do
   if candidate:IsLocalController()==true and live(candidate.Player)and candidate.Player:GetFullName():match('^PalLocalPlayer ')then
    assert(not pc,'Multiple actual local Pal controllers');pc=candidate
   end
  end
  assert(pc and pc:HasAuthority()==true,'Possessed standalone authority controller required')
  local world=pc:GetWorld();assert(live(world)and world:GetFullName():find('MainWorld',1,true),'Actual MainWorld required')
  local controllers=objects('PalPlayerController')
  for _,candidate in ipairs(controllers)do
   if not same(candidate,pc)and same(candidate:GetWorld(),world)and live(candidate.NetConnection)then
    error('Actual remote connected controller exists in the local world')
   end
  end
  local pawn=pc.Pawn
  assert(live(pawn)and pawn:HasAuthority()==true and pawn:IsInitialized()==true,'Initialized authority pawn required')
  assert(same(pawn:GetWorld(),world)and same(pawn:GetController(),pc),'Possessed pawn belongs to another context')
  assert(same(pc:GetDefaultPlayerCharacter(),pawn),'Default player character differs from possessed pawn')
  local gs
  for _,candidate in ipairs(objects('PalGameStateInGame'))do
   if candidate:HasAuthority()==true and same(candidate:GetWorld(),world)then assert(not gs,'Ambiguous MainWorld game state');gs=candidate end
  end
  assert(gs and utility:IsAllLevelLoaded(gs)==true,'Initialized MainWorld levels required')
  assert(same(gameplay:GetGameState(pc),gs),'Native gameplay state differs from the current MainWorld authority')
  trace(world,'net-mode');local net_mode=text(utility:GetNetMode(pc))
  trace(world,'native-standalone');local native_standalone=system:IsStandalone(pc)
  trace(world,'native-dedicated');local dedicated=system:IsDedicatedServer(pc)
  trace(world,'pal-multiplayer');local native_multiplayer=utility:IsMultiplayer(pc)
  trace(world,'native-option-subsystem');local options=utility:GetOptionSubsystem(pc)
  assert(live(options)and same(options:GetWorld(),world),'Actual MainWorld option subsystem required')
  trace(world,'native-world-option-bit');local settings=options.OptionWorldSettings
  assert(type(native_standalone)=='boolean'and type(dedicated)=='boolean'and type(native_multiplayer)=='boolean','Actual native world mode getters required')
  assert(dedicated==false and settings and settings.bIsMultiplay==false,'Actual non-multiplayer local world required')
  local uid=guid(pc:GetPlayerUId());assert(uid~=ZERO,'Actual saved Pal UID required')
  trace(world,'saved-account');local account
  for _,candidate in ipairs(objects('PalPlayerAccount'))do
   local individual=candidate.IndividualHandle
   if live(individual)and guid(individual:GetIndividualID().PlayerUId)==uid then
    local ok,actor=pcall(function()return individual:TryGetIndividualActor()end)
    if ok and same(actor,pawn)and same(actor:GetWorld(),world)then
     assert(not account,'Ambiguous current-world saved player account');account=candidate
    end
   end
  end
  assert(account,'Local Pal UID has no saved account bound to the current actual pawn/world')
  trace(world,'owned-transmitter');local transmitter=pc.Transmitter
  assert(live(transmitter)and same(transmitter:GetOwner(),pc)and same(transmitter:GetWorld(),world),'Local owned transmitter required')
  local component=transmitter:GetPlayer()
  assert(live(component)and same(component:GetOwner(),transmitter),'Owned transmitter player component required')
  trace(world,'loaded-save-manager');local manager
  for _,candidate in ipairs(objects('PalSaveGameManager'))do assert(not manager,'Ambiguous save game manager');manager=candidate end
  assert(manager and manager:IsLoadedWorldData()==true,'Actual loaded save game required')
  local load_failed=text(manager.WorldSaveDataLoadFailedDirectoryName)
  assert(load_failed=='','Actual world load failure recorded')
  -- A released loaded-save UObject is normal after this game's normal SP load.
  -- Keep only live references; ownership still requires the observed native manager/root proof.
  local loaded=manager:GetLoadedWorldSaveData();if not live(loaded)then loaded=nil end
  local world_id=text(gs:GetWorldSaveDirectoryName());assert(#world_id>0,'Actual world directory name unavailable')
  local sid_ok,raw_sid=pcall(function()return text(gs.ServerSessionId)end)
  local observed={mode='standalone',net_mode=net_mode,native_is_standalone=native_standalone,
   native_is_multiplayer=native_multiplayer,world_multiplayer=false,is_dedicated=false,
   world=world,game_state=gs,pc=pc,pawn=pawn,
   saved_account=account,saved_account_address=address(account),save_manager=manager,loaded_save=loaded,owned_transmitter=transmitter,
   option_subsystem=options,controllers=controllers,
   player_component=component,world_id=world_id,host_uid=uid,world_address=address(world),
   save_manager_address=address(manager),loaded_world_native=true,world_load_failed_directory=load_failed,
   loaded_save_address=loaded and address(loaded)or nil,observed_server_session_id=sid_ok and raw_sid or nil}
  return verify_owned(observed)
 end
 -- A proof is shared only inside the one existing game-thread callback. These
 -- native relations are checked on every operation; changes require discovery
 -- and the original loaded-save permission verifier again, even in this frame.
 local function still_current(p)
  assert(type(thread)=='function'and thread()==true,'Standalone context requires game thread')
  local pc,pawn,world,gs=p.pc,p.pawn,p.world,p.game_state
  assert(live(pc)and pc:IsLocalController()==true and pc:HasAuthority()==true
   and live(pc.Player)and pc.Player:GetFullName():match('^PalLocalPlayer '),'Local authority controller changed')
  assert(live(world)and world:GetFullName():find('MainWorld',1,true)and same(pc:GetWorld(),world),'MainWorld changed')
  assert(same(pc.Pawn,pawn)and live(pawn)and pawn:HasAuthority()==true and pawn:IsInitialized()==true
   and same(pawn:GetWorld(),world)and same(pawn:GetController(),pc)
   and same(pc:GetDefaultPlayerCharacter(),pawn),'Possession changed')
  assert(live(gs)and gs:HasAuthority()==true and same(gs:GetWorld(),world)
   and same(gameplay:GetGameState(pc),gs)and utility:IsAllLevelLoaded(gs)==true,'Native game state changed')
  for _,candidate in ipairs(p.controllers)do
   assert(not(live(candidate)and not same(candidate,pc)and same(candidate:GetWorld(),world)
    and live(candidate.NetConnection)),'Remote controller connected')
  end
  local options=utility:GetOptionSubsystem(pc);local settings=options and options.OptionWorldSettings
  assert(same(options,p.option_subsystem)and same(options:GetWorld(),world)and settings and settings.bIsMultiplay==false,
   'Native world options changed')
  assert(text(utility:GetNetMode(pc))==p.net_mode and system:IsStandalone(pc)==p.native_is_standalone
   and system:IsDedicatedServer(pc)==false and utility:IsMultiplayer(pc)==p.native_is_multiplayer,'Native world mode changed')
  assert(guid(pc:GetPlayerUId())==p.host_uid and text(gs:GetWorldSaveDirectoryName())==p.world_id,'Saved host/world changed')
  local account=p.saved_account;local individual=live(account)and account.IndividualHandle
  assert(live(individual)and guid(individual:GetIndividualID().PlayerUId)==p.host_uid
   and same(individual:TryGetIndividualActor(),pawn),'Saved account changed')
  local tx=pc.Transmitter
  assert(same(tx,p.owned_transmitter)and same(tx:GetOwner(),pc)and same(tx:GetWorld(),world),'Owned transmitter changed')
  local component=tx:GetPlayer()
  assert(same(component,p.player_component)and same(component:GetOwner(),tx),'Owned player component changed')
  local manager=p.save_manager
  assert(live(manager)and same(utility:GetSaveGameManager(pc),manager)and manager:IsLoadedWorldData()==true
   and text(manager.WorldSaveDataLoadFailedDirectoryName)=='','Native loaded save manager changed')
  local loaded=manager:GetLoadedWorldSaveData();local loaded_address=live(loaded)and address(loaded)or nil
  assert(loaded_address==p.loaded_save_address,'Native loaded save object changed')
  local gi=gameplay:GetGameInstance(pc)
  assert(live(gi)and text(gi:GetSelectedWorldSaveDirectoryName())==p.world_id,'Native selected world changed')
  return true
 end
 local function referenced_context()
  local observed={};for k,v in pairs(current)do observed[k]=v end
  -- Keep the controller uniqueness/remote-peer gate fresh each frame. The
  -- engine-selected state/account/manager need no repeated global enumeration
  -- while their validated native references and actual relationships still match.
  observed.controllers=objects('PalPlayerController')
  local local_pc
  for _,candidate in ipairs(observed.controllers)do
   if candidate:IsLocalController()==true and live(candidate.Player)and candidate.Player:GetFullName():match('^PalLocalPlayer ')then
    assert(not local_pc,'Multiple actual local Pal controllers');local_pc=candidate
   end
  end
  assert(same(local_pc,observed.pc),'Actual local controller changed')
  still_current(observed)
  return observed
 end
 function api:begin_frame()
  assert(type(thread)=='function'and thread()==true and not in_frame,'One original game-thread frame required')
  in_frame=true;frame_proof=nil;frame_error=nil
 end
 function api:end_frame()in_frame=false;frame_proof=nil;frame_error=nil end
 function api:current()
  if in_frame and frame_error then return nil,frame_error end
  local rediscover=false
  if in_frame and frame_proof then
   local ok=pcall(still_current,frame_proof)
   if ok then return frame_proof end
   frame_proof=nil;rediscover=true
  end
  local ok,observed,observed_key
  if in_frame and current and not rediscover then
   local valid,context=pcall(referenced_context)
   if valid then
    -- The original process/loaded-save/root verifier is never cached across
    -- frames. A permission failure rejects this frame, with no cached fallback.
    ok,observed,observed_key=pcall(verify_owned,context)
   else ok,observed,observed_key=pcall(sample)end
  else ok,observed,observed_key=pcall(sample)end
  if not ok then
   local why=tostring(observed)
   if self.last_error~=why then print('[PalCraft Standalone] fresh sample rejected: '..why..'\n')end
   self.last_error=why;if in_frame then frame_error=why end;return nil,why
  end
  if not current or key~=observed_key then
   self.generation=self.generation+1
   -- Generated only after actual context/ownership validation: a lifecycle ID, not an auth token.
   local nonce=guid(guidlib:NewGuid());assert(nonce~=ZERO,'Actual native realm lifecycle ID unavailable')
   observed.server_session_id='standalone:'..nonce
  else observed.server_session_id=current.server_session_id end
  observed.realm_generation=self.generation;observed.observed_unix=now()
  current=observed;key=observed_key;self.last_error=nil
  if in_frame then frame_proof=observed end;return observed
 end
 function api:validate(proof,pc)
  if type(proof)~='table'then return false,'Standalone proof missing'end
  local actual,why=self:current();if not actual then return false,why end
  if pc and not same(pc,actual.pc)then return false,'Different local controller'end
  return proof.mode=='standalone'and proof.server_session_id==actual.server_session_id
   and proof.realm_generation==actual.realm_generation and proof.world_address==actual.world_address
   and proof.world_id==actual.world_id and proof.host_uid==actual.host_uid
   and proof.world_save_root==actual.world_save_root and proof.process_epoch==actual.process_epoch,
   'Standalone context changed'
 end
 function api:same_world(object,proof)
  local good,why=self:validate(proof);if not good then return false,why end
  return live(object)and same(object:GetWorld(),proof.world),'Object belongs to another actual world'
 end
 function api:invalidate(reason)current=nil;key=nil;frame_proof=nil;frame_error=nil;self.last_error=reason or'standalone_context_retired'end
 function api:status()
  local p,why=self:current()
  if not p then return{authority=false,mode='standalone',reason=why,game_ready=false}end
  return{authority=true,mode='standalone',net_mode=p.net_mode,world_id=p.world_id,
   server_session_id=p.server_session_id,realm_generation=p.realm_generation,host_uid=p.host_uid,
   world_save_root=p.world_save_root,process_epoch=p.process_epoch,observed_unix=p.observed_unix,
   local_controller=true,saved_account=true,owned_transmitter=true,game_ready=false}
 end
 return api
end
return M
