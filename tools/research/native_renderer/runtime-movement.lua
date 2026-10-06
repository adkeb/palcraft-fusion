local ROOT='D:/PalworldServer-LAN/PalCraft-Dev/bridge/'
local J=dofile('D:/PalworldServer-LAN/PalCraft-Client/Pal/Binaries/Win64/ue4ss/Mods/PalCraftClient/Scripts/json.lua')
local pc;for _,p in ipairs(FindAllOf('PalPlayerController')or{})do if p:IsValid()and p.Pawn:IsValid()then pc=p;break end end
assert(pc,'No player')
local companion=assert(_G.PalCraftCollisionCompanion);local form=assert(_G.PalCraftForm)
local desired={};for _,entry in pairs(companion.actors)do for _,h in ipairs(entry.handles)do desired[h]='collision'end;if entry.model then desired[entry.model]='visual'end end
local out={stage='v3_actual_movement',started_unix=os.time(),collision_policy={},samples={},start=pc.Pawn:K2_GetActorLocation()}
for _,actor in ipairs(FindAllOf('Actor')or{})do if actor:IsValid()and desired[actor:GetAddress()]then
 local root=actor.RootComponent
 if root:IsValid()then out.collision_policy[#out.collision_policy+1]={kind=desired[actor:GetAddress()],actor=actor:GetAddress(),enabled=root:GetCollisionEnabled(),water14=root:GetCollisionResponseToChannel(14),fluid19=root:GetCollisionResponseToChannel(19),waterplane25=root:GetCollisionResponseToChannel(25),worldstatic0=root:GetCollisionResponseToChannel(0)}end
end end
local count,elapsed=0,0;local yaw=form.yaw;local function tick()
 count=count+1;local pawn=pc.Pawn;local dt=StaticFindObject('/Script/Engine.Default__GameplayStatics'):GetWorldDeltaSeconds(pawn);elapsed=elapsed+dt
 if elapsed<1.5 then pawn:AddMovementInput({X=1,Y=0,Z=0},1,true)
 elseif elapsed<3 then pawn:AddMovementInput({X=-1,Y=0,Z=0},1,true)end
 local p=pawn:K2_GetActorLocation();local v=pawn:GetVelocity()
 out.samples[#out.samples+1]={elapsed=elapsed,x=p.X,y=p.Y,z=p.Z,vx=v.X,vy=v.Y,vz=v.Z,swimming=pc:IsSwimming(),movement_mode=pawn.CharacterMovement.MovementMode,grounded=pawn.CharacterMovement:IsMovingOnGround()}
 if elapsed<3.4 then ExecuteInGameThreadWithDelay(1,tick)else
  out.elapsed=elapsed;out.finish=p;out.finished_unix=os.time();out.completed=true;out.status=companion.status()
  local f=assert(io.open(ROOT..'native-renderer-movement.json','wb'));f:write(J.encode(out));f:close()
 end
end
ExecuteInGameThreadWithDelay(1,tick)
return{sampling=true,policy_actors=#out.collision_policy,seconds=3.4}
