-- UE4SS adapter. Constructing it is inert; every object access is inside a game-thread method.
local M={}
function M.new(options)
 options=options or{};local P=assert(options.protocol);local config=assert(options.config)
 local api={};local world_settings={}
 local function thread()
  local checker=options.game_thread or IsInGameThread
  assert(type(checker)=='function'and checker()==true,'travel_requires_game_thread')
 end
 local function live(o)return o and o:IsValid()and not o:GetFullName():find('Default__',1,true)end
 local function same(a,b)return live(a)and live(b)and a:GetAddress()==b:GetAddress()end
 function api.valid(pc,binding,authority)
  thread();if not live(pc)or not live(pc.Pawn)or not live(pc.Pawn.CharacterMovement)or not live(pc.Pawn.CapsuleComponent)then return false,'possessed_character_missing'end
  if authority and(not pc:HasAuthority()or not pc.Pawn:HasAuthority())then return false,'pal_server_authority_required'end
  if options.verify_identity then return options.verify_identity(pc,binding,authority)end
  -- Server resolution checks these too; repeat at the actual mutation boundary.
  if options.readers then
   local g=pc:GetPlayerUId();local uid=options.readers.guid_to_string({A=g.A,B=g.B,C=g.C,D=g.D}):lower()
   if uid~=binding.pal_uid then return false,'pal_identity_changed'end
  else return false,'pal_identity_verifier_missing'end
  local world=pc:GetWorld();local state
  for _,gs in ipairs(FindAllOf('PalGameStateInGame')or{})do
   if live(gs)and same(gs:GetWorld(),world)then
    assert(not state,'ambiguous_pal_game_state');state=gs
   end
  end
  if not state then return false,'pal_game_state_missing'end
  local function str(x)return type(x)=='string'and x or x:ToString()end
  if str(state.ServerSessionId)~=binding.server_session_id or str(state:GetWorldSaveDirectoryName())~=binding.world_id then return false,'pal_world_changed'end
  return true
 end
 function api.position(pc)
  thread();assert(live(pc)and live(pc.Pawn),'possessed_character_missing');local p=pc.Pawn:K2_GetActorLocation()
  local out={X=p.X,Y=p.Y,Z=p.Z};assert(P.ue(out),'nonfinite_pal_position');return out
 end
 function api.snapshot(pc)
  thread();local pawn=pc.Pawn;local m=pawn.CharacterMovement;local r=pc:GetControlRotation()
  local h=pawn.CapsuleComponent:GetScaledCapsuleHalfHeight()
  assert(type(h)=='number'and h>0 and h<500,'invalid_pal_capsule')
  return{position=api.position(pc),rotation={Yaw=r.Yaw,Pitch=r.Pitch,Roll=r.Roll},half_height=h,
   movement_mode=m.MovementMode,custom_movement_mode=m.CustomMovementMode,pawn_address=pawn:GetAddress()}
 end
 function api.hold(pc,authority,restore_state)
  thread();local pawn=pc.Pawn;local m=pawn.CharacterMovement
  local lock={pc=pc,pawn=pawn,movement=m,mode=m.MovementMode,custom=m.CustomMovementMode}
  if authority and restore_state then lock.mode=restore_state.movement_mode;lock.custom=restore_state.custom_movement_mode end
  -- Store each acquired entry immediately so a failed later call can unwind precisely.
  local ok,err=pcall(function()
   pc:SetIgnoreMoveInput(true);lock.move=true;pc:SetIgnoreLookInput(true);lock.look=true
   if authority then m:StopMovementImmediately();m:DisableMovement();lock.disabled=true end
  end)
  if not ok then api.release(lock);error(err)end;return lock
 end
 function api.release(lock)
  thread();if not lock then return end
  if live(lock.pc)then
   if lock.move then lock.pc:SetIgnoreMoveInput(false);lock.move=false end
   if lock.look then lock.pc:SetIgnoreLookInput(false);lock.look=false end
  end
  -- Never change a replacement pawn after respawn or reconnect.
  if lock.disabled and live(lock.movement)and live(lock.pc)and same(lock.pc.Pawn,lock.pawn)then
   lock.movement:SetMovementMode(lock.mode,lock.custom or 0);lock.disabled=false
  end
 end
 function api.safety(pc,mapping,target,binding)
  thread();local valid,why=api.valid(pc,binding,true);if not valid then return false,why end
  local h=pc.Pawn.CapsuleComponent:GetScaledCapsuleHalfHeight()
  if not P.contains(config.world_bounds,target,h)or not P.contains(mapping.region_bounds,target,h)then return false,'pal_world_or_region_bounds'end
  local world=pc:GetWorld();local id=world:GetAddress();local ws=world_settings[id]
  if not live(ws)then
   local persistent=world.PersistentLevel
   if not live(persistent)then return false,'persistent_level_unavailable'end
   -- WorldPartition tiles each own WorldSettings. GetWorld alone is not a unique selector.
   ws=nil;for _,s in ipairs(FindAllOf('WorldSettings')or{})do
    if live(s)and same(s:GetWorld(),world)and same(s:GetOuter(),persistent)then
     assert(not ws,'ambiguous_persistent_world_settings');ws=s
    end
   end
   world_settings[id]=ws
  end
  if not ws then return false,'world_settings_unavailable'end
  if type(ws.KillZ)~='number'or target.Z-h<=ws.KillZ+config.kill_z_margin_cm then return false,'pal_kill_z'end
  -- Home Overworld intentionally contains existing Pal terrain. Auxiliary regions must be clear of saved objects.
  if mapping.slot~=0 then for _,object in ipairs(FindAllOf('PalMapObject')or{})do
   if live(object)and same(object:GetWorld(),world)then
    local p=object:K2_GetActorLocation();if P.contains(mapping.region_bounds,{X=p.X,Y=p.Y,Z=p.Z})then return false,'saved_pal_map_object_in_region'end
   end
  end end
  if options.streaming_ready then
   local ready,detail=options.streaming_ready(pc,mapping,target);if ready~=true then return false,detail or'pal_streaming_pending'end
  end
  return true,{kill_z=ws.KillZ,bounds_checks=ws.bEnableWorldBoundsChecks,
   streaming='persistent_UWorld_native_scene',world_address=id}
 end
 function api.teleport(pc,target,rotation)
  thread();assert(pc:HasAuthority()and pc.Pawn:HasAuthority(),'pal_server_authority_required')
  if config.teleport_api=='pal_utility'then
   local lib=StaticFindObject('/Script/Pal.Default__PalUtility');assert(lib and lib:IsValid(),'pal_utility_unavailable')
   -- Both SDK header and live ObjectDump have this FVector/FQuat/bool/bool -> bool signature.
   local moved=lib:Teleport(pc.Pawn,target,P.quaternion(rotation),false,false)
   if moved~=true then return false,'pal_utility_teleport_rejected'end
  elseif config.teleport_api=='k2_teleport'then
   if pc.Pawn:K2_TeleportTo(target,rotation)~=true then return false,'k2_teleport_rejected'end
  else return false,'unsupported_teleport_api'end
  return true,api.position(pc)
 end
 return api
end
return M
