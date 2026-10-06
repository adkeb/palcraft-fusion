assert(IsInGameThread())
local dir='Z:/path/to/workspace/work/minecraft-fusion/entity-combat-actual/'
local J=dofile('D:/PalworldServer-LAN/PalCraft-Client/Pal/Binaries/Win64/ue4ss/Mods/PalCraftClient/Scripts/json.lua')
_G.PalCraftEntityFoodLease=dofile(dir..'normal_food_operator.lua').new{json=J}
local c=_G.PalCraftClientFeatures.composition.features.commands
return {read_only=true,food_attempts=0,items_granted=0,hp_writes=0,commands=c.instance.status(),
 form=_G.PalCraftForm.status(),vitals=_G.PalCraftEntityFoodLease.observe()}
