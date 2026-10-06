local ROOT='D:/PalworldServer-LAN/PalCraft-Dev/bridge/'
local J=dofile('D:/PalworldServer-LAN/PalCraft-Client/Pal/Binaries/Win64/ue4ss/Mods/PalCraftClient/Scripts/json.lua')
local out={stage='v3_replay_rotation',started_unix=os.time(),samples={},replays=0}
local form=assert(_G.PalCraftForm)
assert(form.active,'Enter MC form first')
local yaw,pitch=form.yaw,form.pitch
local step=0
local function save()local f=assert(io.open(ROOT..'native-renderer-stress.json','wb'));f:write(J.encode(out));f:close()end
local function tick()
 step=step+1;form.yaw=yaw+step*30;form.pitch=-12
 if step%12==1 then _G.PalCraftReloadCollisions();out.replays=out.replays+1 end
 local companion=_G.PalCraftCollisionCompanion
 if companion then out.samples[#out.samples+1]={step=step,unix=os.time(),yaw=form.yaw,status=companion.status()}end
 if step<72 then ExecuteInGameThreadWithDelay(150,tick)else form.yaw=yaw;form.pitch=pitch;out.finished_unix=os.time();out.completed=true;out.final=companion and companion.status();save()end
 if step%12==0 then save()end
end
ExecuteInGameThreadWithDelay(150,tick)
return{stress_started=true,replays=6,turns=6,seconds=10.8}
