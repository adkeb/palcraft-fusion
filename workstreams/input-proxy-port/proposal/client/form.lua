-- Palworld supplies physical locomotion. Only this module owns MC-form input.
-- Acquire one ignore-input stack entry and release exactly that entry on exit.
local M={active=false,hidden_widgets={},weapons={},transitions=0,weapon_scans=0,attachment_scans=0}
local FLAG=FName('PalCraftForm')
local function live(o)return o and o:IsValid()end
local function same(a,b)return live(a)and live(b)and a:GetAddress()==b:GetAddress()end
local function fresh(input)
 if not input or input.stale then return false end
 local age=os.time()-(input.unix or 0)
 return age>=-2 and age<3
end
function M.observe_widgets(widgets)
 if not M.active then return end
 for _,w in ipairs(widgets)do
  if live(w)and w:IsInViewport()then
   local id=w:GetAddress();local old=M.hidden_widgets[id]
   if not old then M.hidden_widgets[id]={object=w,visibility=w:GetVisibility(),opacity=w:GetRenderOpacity()}end
   if w:GetVisibility()~=2 then w:SetVisibility(2)end
   if w:GetRenderOpacity()~=0 then w:SetRenderOpacity(0)end
  end
 end
 for id,v in pairs(M.hidden_widgets)do if not live(v.object)then M.hidden_widgets[id]=nil end end
end
local function remember(w,owned)
 local id=w:GetAddress()
 if not M.weapons[id]then M.weapons[id]={object=w,hidden=w.bHidden}end
 if owned then M.weapons[id].owned=true end
 return id
end
local function maintain_weapons(discover_owned)
 if discover_owned then
  M.weapon_scans=M.weapon_scans+1
  for _,w in ipairs(FindAllOf('PalWeaponBase')or{})do if live(w)and same(w:GetOwner(),M.pawn)then remember(w,true)end end
 end
 -- GetAttachedActors is a local hierarchy query. Back weapons have Owner=null
 -- and are not PalWeaponBase, so a global owned-weapon scan misses them.
 M.attachment_scans=M.attachment_scans+1
 local attached,seen={},{};M.pawn:GetAttachedActors(attached,true,true)
 for _,parameter in ipairs(attached)do
  local w=parameter:get()
  if live(w)then
   local name=w:GetFullName()
   if w:IsA('/Script/Pal.PalWeaponBase')or name:match('^BP_BackWeapon_')or name:match('^BP_Glider_')then seen[remember(w,false)]=true end
  end
 end
 for id,v in pairs(M.weapons)do
  if not live(v.object)then M.weapons[id]=nil
  elseif not seen[id]and not(v.owned and same(v.object:GetOwner(),M.pawn))then v.object:SetActorHiddenInGame(v.hidden);M.weapons[id]=nil
  elseif not v.object.bHidden then v.object:SetActorHiddenInGame(true)end
 end
 if live(M.pawn)and not M.pawn.bHidden then M.pawn:SetActorHiddenInGame(true)end
 for id,v in pairs(M.hidden_widgets)do
  if not live(v.object)then M.hidden_widgets[id]=nil
  else if v.object:GetVisibility()~=2 then v.object:SetVisibility(2)end;if v.object:GetRenderOpacity()~=0 then v.object:SetRenderOpacity(0)end end
 end
end
local function leave(reason)
 if not M.active then return end
 M.active=false;M.transitions=M.transitions+1;M.last_exit=reason
 if live(M.pawn)then
  M.pawn:SetActorHiddenInGame(M.pawn_hidden);M.pawn:StopJumping()
  if live(M.movement)then M.movement.MaxWalkSpeed=M.speed;M.movement.JumpZVelocity=M.jump end
 end
 for _,v in pairs(M.weapons)do if live(v.object)then v.object:SetActorHiddenInGame(v.hidden)end end;M.weapons={}
 for _,v in pairs(M.hidden_widgets)do if live(v.object)then v.object:SetVisibility(v.visibility);v.object:SetRenderOpacity(v.opacity)end end;M.hidden_widgets={}
 local pc=M.pc
 if live(pc)then
  pc:SetDisableInputFlag(FLAG,false)
  if M.move_lock then pc:SetIgnoreMoveInput(false)end
  if M.look_lock then pc:SetIgnoreLookInput(false)end
  pc.bShowMouseCursor=M.cursor
  pc:SetDisableSetViewTargetFlag(FLAG,false)
  local view=live(M.view)and M.view or pc.Pawn
  if live(view)then pc:SetViewTargetWithBlend(view,0,0,0,false)end
 end
 if live(M.camera)then M.camera:K2_DestroyActor()end
 M.camera=nil;M.pc=nil;M.pawn=nil;M.movement=nil;M.capsule=nil
 M.move_lock=false;M.look_lock=false;M.jump_down=false
end
function M.tick(pc,input,now_ms)
 now_ms=now_ms or os.clock()*1000
 if M.active and(not same(pc,M.pc)or not same(pc.Pawn,M.pawn)or not live(M.camera))then leave('possession_changed')end
 if not(fresh(input)and input.build==true)then leave('mode_off_or_stale_input');return false end
 local pawn=pc.Pawn
 if not M.active then
  M.pc=pc;M.pawn=pawn;M.view=pc:GetViewTarget();M.movement=pawn.CharacterMovement;M.capsule=pawn.CapsuleComponent
  M.speed=M.movement.MaxWalkSpeed;M.jump=M.movement.JumpZVelocity;M.pawn_hidden=pawn.bHidden;M.cursor=pc.bShowMouseCursor
  M.camera=pc:GetWorld():SpawnActor(StaticFindObject('/Script/Engine.CameraActor'),pc.PlayerCameraManager:GetCameraLocation(),pc:GetControlRotation())
  assert(live(M.camera),'MC camera unavailable')
  M.camera.CameraComponent:SetFieldOfView(90)
  M.active=true;M.transitions=M.transitions+1
  M.mouse_x=input.mouse_x or 0;M.mouse_y=input.mouse_y or 0;M.jump_down=false;M.frames=0
  M.input_generation=input.generation;M.was_looking=false
  local r=pc:GetControlRotation();M.yaw=(r.Yaw+180)%360-180;M.pitch=math.max(-85,math.min(85,(r.Pitch+180)%360-180))
  pc:SetDisableInputFlag(FLAG,true)
  pc:SetIgnoreMoveInput(true);M.move_lock=true;pc:SetIgnoreLookInput(true);M.look_lock=true
  pc:SetDisableSetViewTargetFlag(FLAG,false);pc:SetViewTargetWithBlend(M.camera,0,0,0,false);pc:SetDisableSetViewTargetFlag(FLAG,true)
  pawn:SetActorHiddenInGame(true);M.movement:StopMovementImmediately();M.movement.JumpZVelocity=420
  maintain_weapons(true);M.next_weapons=now_ms+100
 end
 M.frames=M.frames+1
 local looking=not input.menu and input.focus==true
 local mx,my=input.mouse_x or 0,input.mouse_y or 0
 local dx,dy=mx-M.mouse_x,my-M.mouse_y
 -- Baseline cumulative counts on focus/menu/reconnect transitions; never replay
 -- movement collected while the user was interacting with another app or GUI.
 if looking and M.was_looking and M.input_generation==input.generation then
  M.yaw=(M.yaw+dx*0.10+180)%360-180;M.pitch=math.max(-85,math.min(85,M.pitch-dy*0.10))
 end
 M.mouse_x=mx;M.mouse_y=my;M.was_looking=looking;M.input_generation=input.generation
 local rotation={Pitch=M.pitch,Yaw=M.yaw,Roll=0};pc:SetControlRotation(rotation)
 pc.bShowMouseCursor=input.menu==true
 local speed=input.sneak and 130 or(input.sprint and 560 or 430)
 if M.movement.MaxWalkSpeed~=speed then M.movement.MaxWalkSpeed=speed end
 if looking then
  local forward,strafe=input.forward or 0,input.strafe or 0
  local magnitude=math.sqrt(forward*forward+strafe*strafe)
  if magnitude>1 then forward=forward/magnitude;strafe=strafe/magnitude end
  local y=M.yaw*math.pi/180
  if forward~=0 then pawn:AddMovementInput({X=math.cos(y),Y=math.sin(y),Z=0},forward,true)end
  if strafe~=0 then pawn:AddMovementInput({X=-math.sin(y),Y=math.cos(y),Z=0},strafe,true)end
 end
 local jumping=looking and input.jump==true
 if jumping and not M.jump_down then pawn:Jump()elseif not jumping and M.jump_down then pawn:StopJumping()end;M.jump_down=jumping
 local p=pawn:K2_GetActorLocation();p.Z=p.Z-M.capsule:GetScaledCapsuleHalfHeight()+(input.sneak and 147 or 162)
 M.camera:K2_SetActorLocation(p,false,{},true);M.camera:K2_SetActorRotation(rotation,false)
 if now_ms>=M.next_weapons then maintain_weapons(false);M.next_weapons=now_ms+100 end
 return true
end
function M.status()
 local weapons,widgets=0,0;for _ in pairs(M.weapons)do weapons=weapons+1 end;for _ in pairs(M.hidden_widgets)do widgets=widgets+1 end
 return{active=M.active,transitions=M.transitions,yaw=M.yaw,pitch=M.pitch,camera=live(M.camera)and M.camera:GetFullName()or nil,hidden_weapons=weapons,hidden_widgets=widgets,weapon_scans=M.weapon_scans,attachment_scans=M.attachment_scans,last_exit=M.last_exit}
end
-- Called on the game thread after authoritative travel replication arrives.
-- This changes only the camera/control view and never teleports the pawn.
function M.sync_view(pc,pal_yaw,pal_pitch,input)
 M.yaw=(pal_yaw+180)%360-180;M.pitch=math.max(-85,math.min(85,(pal_pitch+180)%360-180))
 M.mouse_x=input and input.mouse_x or M.mouse_x or 0;M.mouse_y=input and input.mouse_y or M.mouse_y or 0
 M.input_generation=input and input.generation or M.input_generation;M.was_looking=false
 local rotation={Yaw=M.yaw,Pitch=M.pitch,Roll=0};if live(pc)then pc:SetControlRotation(rotation)end
 if M.active and live(M.camera)and live(M.pawn)then
  local p=M.pawn:K2_GetActorLocation();p.Z=p.Z-M.capsule:GetScaledCapsuleHalfHeight()+(input and input.sneak and 147 or 162)
  M.camera:K2_SetActorLocation(p,false,{},true);M.camera:K2_SetActorRotation(rotation,false)
 end
 return true
end
function M.stop(pc,reason)leave(reason or(type(pc)=='string'and pc)or'stop')end
return M
