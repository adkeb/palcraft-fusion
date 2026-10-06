-- One camera step, called only under the coordinator's explicit RPC lease.
local pc;for _,p in ipairs(FindAllOf('PalPlayerController')or{})do if p:IsValid()and p.Pawn:IsValid()then pc=p;break end end
assert(pc,'No possessed player')
local companion=assert(_G.PalCraftCollisionCompanion)
local state=_G.PalCraftAnchorViewProbe
if not state then
 local key,entry
 for k,e in pairs(companion.actors)do if e.model and e.id=='minecraft:oak_planks'then key,entry=k,e;break end end
 assert(entry,'No native MC model')
 local target;for _,a in ipairs(FindAllOf('Actor')or{})do if a:IsValid()and a:GetAddress()==entry.model then target=a;break end end
 assert(target,'Native model actor unavailable')
 state={pc=pc,view=pc:GetViewTarget(),rotation=pc:GetControlRotation(),model=target,key=key,step=0}
 _G.PalCraftAnchorViewProbe=state
end
assert(state.pc:GetAddress()==pc:GetAddress()and state.model:IsValid(),'Probe lifetime changed')
state.step=state.step+1
local offsets={0,6,-6};local delta=assert(offsets[state.step],'Three angle limit')
pc:SetControlRotation({Pitch=state.rotation.Pitch,Yaw=state.rotation.Yaw+delta,Roll=state.rotation.Roll})
return{step=state.step,offset_degrees=delta,key=state.key,actor=state.model:GetAddress(),
 model_world=state.model:K2_GetActorLocation(),model_scale=state.model:GetActorScale3D(),model_rotation=state.model:K2_GetActorRotation(),
 player_location=pc.Pawn:K2_GetActorLocation(),original_rotation=state.rotation,view=pc:GetViewTarget():GetFullName()}
