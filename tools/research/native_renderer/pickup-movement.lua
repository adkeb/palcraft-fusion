local pc;for _,p in ipairs(FindAllOf('PalPlayerController')or{})do if p:IsValid()and p.Pawn:IsValid()then pc=p;break end end
assert(pc,'No player');local elapsed=0
local function tick()
 elapsed=elapsed+StaticFindObject('/Script/Engine.Default__GameplayStatics'):GetWorldDeltaSeconds(pc.Pawn)
 pc.Pawn:AddMovementInput({X=0,Y=1,Z=0},1,true)
 if elapsed<.45 then ExecuteInGameThreadWithDelay(1,tick)end
end
ExecuteInGameThreadWithDelay(1,tick)
return{normal_movement_seconds=.45,direction={0,1,0}}
