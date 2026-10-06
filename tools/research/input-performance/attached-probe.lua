local p=assert(_G.PalCraftForm.pawn);local a={};p:GetAttachedActors(a,true,true)
local out={}
for _,v in ipairs(a)do local o=v:get()
 local ok,parent=pcall(function()return o:GetClass():GetSuperStruct():GetFullName()end)
 out[#out+1]={name=o:GetFullName(),hidden=o.bHidden,parent=ok and parent or tostring(parent)}
end
return out
