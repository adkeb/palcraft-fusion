local ROOT='D:/PalworldServer-LAN/PalCraft-Dev/bridge/'
local J=dofile('D:/PalworldServer-LAN/PalCraft-Client/Pal/Binaries/Win64/ue4ss/Mods/PalCraftClient/Scripts/json.lua')
local label='v15-mc-idle'
local seconds=20
local pc
for _,p in ipairs(FindAllOf('PalPlayerController')or{})do if p:IsValid()and p.Pawn:IsValid()and not p:GetFullName():find('Default__',1,true)then pc=p;break end end
assert(pc,'No player')
local s=StaticFindObject('/Script/Engine.Default__GameplayStatics')
local start=s:GetRealTimeSeconds(pc);local previous=start;local rows={}
local function finish()
 local intervals,deltas,peak=0,0,0
 for _,r in ipairs(rows)do intervals=intervals+r.interval_ms;deltas=deltas+r.world_ms;peak=math.max(peak,r.speed_cm_s)end
 local out={label=label,seconds=s:GetRealTimeSeconds(pc)-start,samples=#rows,callback_hz=#rows/(s:GetRealTimeSeconds(pc)-start),world_frame_mean_ms=deltas/#rows,peak_speed_cm_s=peak,form=_G.PalCraftForm.status(),pal_health_policy='unchanged_no_grants_or_healing',remote_environment={cpu_cap_percent=50,turbo=false,gpu_cap_watts=400},rows=rows,unix=os.time()}
 local f=assert(io.open(ROOT..'input-performance-'..label..'.json','wb'));f:write(J.encode(out));f:close()
end
local function sample()
 if not pc:IsValid()or not pc.Pawn:IsValid()then return end
 local now=s:GetRealTimeSeconds(pc);local p=pc.Pawn:K2_GetActorLocation();local v=pc.Pawn:GetVelocity()
 rows[#rows+1]={elapsed=now-start,interval_ms=(now-previous)*1000,world_ms=s:GetWorldDeltaSeconds(pc)*1000,speed_cm_s=math.sqrt(v.X*v.X+v.Y*v.Y),x=p.X,y=p.Y,z=p.Z,yaw=pc:GetControlRotation().Yaw}
 previous=now
 if now-start<seconds then ExecuteInGameThreadWithDelay(1,sample)else finish()end
end
ExecuteInGameThreadWithDelay(1,sample)
return{sampling=true,label=label,seconds=seconds}
