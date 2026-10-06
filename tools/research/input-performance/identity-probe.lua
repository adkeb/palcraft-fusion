local f=assert(_G.PalCraftForm);local pc=assert(f.pc,'MC form must own local controller for probe')
assert(f.active and pc:IsValid()and pc.Pawn:IsValid(),'No active local MC form')
local pawn=pc.Pawn
local function desc(o)if o and o:IsValid()then return{address=o:GetAddress(),name=o:GetFullName()}end;return{valid=false}end
local function guid(g)return('%08x-%04x-%04x-%04x-%04x%08x'):format(g.A&0xffffffff,(g.B>>16)&0xffff,g.B&0xffff,(g.C>>16)&0xffff,g.C&0xffff,g.D&0xffffffff)end
local out={unix=os.time(),controller=desc(pc),pawn=desc(pawn),world=desc(pc:GetWorld()),pal_uid=guid(pc:GetPlayerUId()),form=f.status(),optional={},errors={}}
local function capture(k,fn)local ok,v=pcall(fn);if ok then out.optional[k]=v else out.errors[k]=tostring(v)end end
capture('local_player',function()return desc(pc.Player)end)
capture('player_state',function()return desc(pc.PlayerState)end)
capture('pawn_player_state',function()return desc(pawn.PlayerState)end)
capture('character_name',function()return pc.PlayerState:GetPlayerName():ToString()end)
capture('pawn_controller',function()return desc(pawn:GetController())end)
capture('camera_owner',function()return desc(pc.PlayerCameraManager.PCOwner)end)
capture('weapon_component',function()return desc(pawn.WeaponEquipComponent)end)
capture('attached',function()
 local a={};local result=pawn:GetAttachedActors(a,true,true)
 local q={parameter_type=type(a),return_type=type(result),names={}}
 for _,o in ipairs(a)do q.names[#q.names+1]=desc(o)end
 if type(result)=='userdata'then result:ForEach(function(_,value)local o=value:get();q.names[#q.names+1]=desc(o)end)end
 return q
end)
for _,g in ipairs(FindAllOf('PalGameStateInGame')or{})do
 if g:IsValid()and g:GetWorld():GetAddress()==pc:GetWorld():GetAddress()then
  out.game_state=desc(g);out.server_session_id=type(g.ServerSessionId)=='string'and g.ServerSessionId or g.ServerSessionId:ToString();break
 end
end
return out
