local form=assert(_G.PalCraftForm);assert(form.active,'MC form not active')
local pc;for _,p in ipairs(FindAllOf('PalPlayerController')or{})do if p:IsValid()and p.Pawn:IsValid()then pc=p;break end end
assert(pc,'No player');local O=assert(_G.PalCraftCollisionCompanion).origin
local camera=pc.PlayerCameraManager:GetCameraLocation()
-- Existing nearby plank, approached from the current stone floor. No teleport.
local target={X=O.X-4.7*100,Y=O.Y+14.6*100,Z=O.Z}
local dx,dy,dz=target.X-camera.X,target.Y-camera.Y,target.Z-camera.Z
form.yaw=math.atan(dy,dx)*180/math.pi;form.pitch=math.atan(dz,math.sqrt(dx*dx+dy*dy))*180/math.pi
return{target={-4.7,64,-14.6},yaw=form.yaw,pitch=form.pitch}
