-- The graphical-lease owner may queue this ONCE through mac/queue_operation.py.
-- Only reads objects and writes acceptance-probe.ndjson. No gameplay mutation.
local ROOT='D:/PalworldServer-LAN/PalCraft-Dev/bridge/'
local SCRIPTS='D:/PalworldServer-LAN/PalCraft-Client/Pal/Binaries/Win64/ue4ss/Mods/PalCraftClient/Scripts/'
local J=dofile(SCRIPTS..'json.lua')
local function live(o)return o and o:IsValid()and not o:GetFullName():find('Default__',1,true)end
local function read(p)local f=io.open(p,'rb');if not f then return end;local s=f:read('*a');f:close();local ok,v=pcall(J.decode,s);if ok then return v end end
local identity=assert(read(ROOT..'lab-identity.json'),'BridgeLab identity required')
local matched=false
for _,g in ipairs(FindAllOf('PalGameStateInGame')or{})do
 if live(g)then local id=g.ServerSessionId;if type(id)~='string'then id=id:ToString()end
  if id==identity.server_session_id then matched=true;break end
 end
end
assert(matched,'Observation is restricted to the matching BridgeLab session')
if _G.PalCraftAcceptanceProbe and _G.PalCraftAcceptanceProbe.running then
 return{sampling=true,session_id=_G.PalCraftAcceptanceProbe.session_id,already_running=true}
end
local P={running=true,session_id='qa-'..os.time(),profile_id='night_low_power',started_unix=os.time(),duration_s=180,elapsed_s=0,frames=0,window_s=0,frame_ms=J.array(),actor_cache={},scan_s=-10}
_G.PalCraftAcceptanceProbe=P
local lib=StaticFindObject('/Script/Engine.Default__GameplayStatics')
local pc
local function controller()
 if live(pc)and live(pc.Pawn)and live(pc.PlayerCameraManager)then return pc end
 for _,v in ipairs(FindAllOf('PalPlayerController')or{})do if live(v)and live(v.Pawn)and live(v.PlayerCameraManager)then pc=v;return pc end end
end
local function vector(p)return{p.X,p.Y,p.Z}end
local function actors()
 local companion=_G.PalCraftCollisionCompanion
 if not companion then return{},{unavailable=true}end
 -- Cache wrappers at most every 10s, never once per frame; sample <=16 blocks.
 if P.elapsed_s-P.scan_s>=10 then
  P.scan_s=P.elapsed_s;P.actor_cache={};local wanted={}
  for _,a in pairs(companion.actors or{})do
   if a.model then wanted[a.model]=true end
   for _,h in ipairs(a.handles or{})do wanted[h]=true end
  end
  for _,a in ipairs(FindAllOf('Actor')or{})do if live(a)and wanted[a:GetAddress()]then P.actor_cache[a:GetAddress()]=a end end
 end
 local out={};local keys={}
 for k in pairs(companion.actors or{})do keys[#keys+1]=k end;table.sort(keys)
 for i=1,math.min(16,#keys)do
  local k=keys[i];local entry=companion.actors[k];local address=entry.model or(entry.handles or{})[1];local a=P.actor_cache[address]
  if live(a)then local r=a:K2_GetActorRotation();out[k]={address=tostring(address),id=entry.id,position=vector(a:K2_GetActorLocation()),rotation={r.Pitch,r.Yaw,r.Roll}}end
 end
 local ok,status=pcall(companion.status);return out,ok and status or{error=tostring(status)}
end
local function state()
 local current_match=false
 for _,g in ipairs(FindAllOf('PalGameStateInGame')or{})do
  if live(g)then local id=g.ServerSessionId;if type(id)~='string'then id=id:ToString()end
   if id==identity.server_session_id then current_match=true;break end
  end
 end
 if not current_match then return{status='other_or_unloaded_session'}end
 local p=controller();if not p then return{status='no_possessed_character'}end
 local pawn=p.Pawn;local movement=pawn.CharacterMovement;local velocity=pawn:GetVelocity();local camera=p.PlayerCameraManager
 local r=camera:GetCameraRotation();local form=_G.PalCraftForm;local owned={}
 for _,w in ipairs(FindAllOf('PalWeaponBase')or{})do
  if live(w)then local owner=w:GetOwner();if live(owner)and owner:GetAddress()==pawn:GetAddress()then owned[w:GetFullName()]={hidden=w.bHidden,position=vector(w:K2_GetActorLocation())}end end
 end
 local sampled,status=actors();local view=p:GetViewTarget()
 local result={status='in_bridgelab',pawn=pawn:GetFullName(),pawn_address=tostring(pawn:GetAddress()),pawn_hidden=pawn.bHidden,
  pawn_position=vector(pawn:K2_GetActorLocation()),camera_position=vector(camera:GetCameraLocation()),camera_yaw=r.Yaw,camera_pitch=r.Pitch,
  speed_cm_s=math.sqrt(velocity.X*velocity.X+velocity.Y*velocity.Y),velocity=vector(velocity),walk_speed=movement.MaxWalkSpeed,jump_velocity=movement.JumpZVelocity,
  grounded=movement:IsMovingOnGround(),movement_mode=movement.MovementMode,swimming=p:IsSwimming(),ignore_move=p:IsMoveInputIgnored(),ignore_look=p:IsLookInputIgnored(),
  view=live(view)and view:GetFullName()or'invalid',form=form and form.status()or{unavailable=true},weapons=owned,actors=sampled,collision=status}
 -- Optional read-only health hook supplied by the entity owner; no invented HP.
 if type(_G.PalCraftAcceptanceVitals)=='function'then local ok,v=pcall(_G.PalCraftAcceptanceVitals,p);if ok then result.vitals=v end end
 return result
end
local function emit(ending)
 local ok,s=pcall(state)
 local row={schema_version=1,session_id=P.session_id,profile_id=P.profile_id,unix=os.time(),elapsed_wall_s=os.time()-P.started_unix,elapsed_s=P.elapsed_s,frames=P.frames,window_s=P.window_s,
  frame_ms=P.frame_ms,frame_method='UE_GameplayStatics_GetWorldDeltaSeconds',state=ok and s or{status='probe_error',error=tostring(s)},ending=ending or false}
 local f=assert(io.open(ROOT..'acceptance-probe.ndjson','ab'));f:write(J.encode(row)..'\n');f:close()
 P.frame_ms=J.array();P.window_s=0
end
local tick
tick=function()
 if not P.running then return end
 local ok,e=pcall(function()
  local p=controller();local dt=live(p)and lib:GetWorldDeltaSeconds(p.Pawn)or .05
  if type(dt)~='number'or dt<=0 then dt=.001 end
  P.elapsed_s=P.elapsed_s+dt;P.window_s=P.window_s+dt;P.frames=P.frames+1
  if live(p)then P.frame_ms[#P.frame_ms+1]=dt*1000 end
  if P.window_s>=1 then emit(false)end
  if os.time()-P.started_unix>=P.duration_s then P.running=false;emit(true)end
 end)
 if not ok then P.running=false;P.error=tostring(e);pcall(emit,true)end
 if P.running then ExecuteInGameThreadWithDelay(1,tick)end
end
ExecuteInGameThreadWithDelay(1,tick)
return{sampling=true,session_id=P.session_id,duration_s=P.duration_s,output=ROOT..'acceptance-probe.ndjson',read_only_gameplay=true}
