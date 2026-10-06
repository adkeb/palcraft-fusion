local state=_G.PalCraftAnchorViewProbe
if not state then return{restored=true,probe_absent=true}end
if state.pc:IsValid()then
 state.pc:SetControlRotation(state.rotation)
 if state.view and state.view:IsValid()then state.pc:SetViewTargetWithBlend(state.view,0,0,0,false)end
end
_G.PalCraftAnchorViewProbe=nil
return{restored=true,rotation=state.rotation,view=state.view and state.view:IsValid()and state.view:GetFullName()or nil}
