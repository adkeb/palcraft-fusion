local form=assert(_G.PalCraftForm);assert(form.active)
local pc;for _,p in ipairs(FindAllOf('PalPlayerController')or{})do if p:IsValid()and p.Pawn:IsValid()then pc=p;break end end
local O=assert(_G.PalCraftCollisionCompanion).origin
local camera=pc.PlayerCameraManager:GetCameraLocation()
local target={X=O.X-4*100,Y=O.Y+9.5*100,Z=O.Z+.5*100}
local dx,dy,dz=target.X-camera.X,target.Y-camera.Y,target.Z-camera.Z
form.yaw=math.atan(dy,dx)*180/math.pi;form.pitch=math.atan(dz,math.sqrt(dx*dx+dy*dy))*180/math.pi
return{target={-4,64.5,-9.5},yaw=form.yaw,pitch=form.pitch,camera=camera}
