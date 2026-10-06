assert(IsInGameThread(),'Trusted current RPC required')
local dir='Z:/path/to/workspace/work/minecraft-fusion/entity-combat-actual/'
local J=dofile('D:/PalworldServer-LAN/PalCraft-Client/Pal/Binaries/Win64/ue4ss/Mods/PalCraftClient/Scripts/json.lua')
_G.PalCraftEntityFoodLease=dofile(dir..'normal_food_operator.lua').new{json=J}
local out={read_only=true,items_granted=0,hp_writes=0,food_attempts=0}
local ok,r=pcall(function()return dofile(dir..'pal_bag_food_inspect.lua').run()end)
out.pal_bag={ok=ok,result=ok and r or nil,error=not ok and tostring(r)or nil}
ok,r=pcall(_G.PalCraftEntityFoodLease.observe)
out.vitals={ok=ok,result=ok and r or nil,error=not ok and tostring(r)or nil}
ok,r=pcall(_G.PalCraftEntityFoodLease.request_inspection)
out.mc_inspection_request={ok=ok,result=ok and r or nil,error=not ok and tostring(r)or nil}
out.form=_G.PalCraftForm and _G.PalCraftForm.status()or nil
return out
