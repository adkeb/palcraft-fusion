local E=dofile('work/minecraft-fusion/entity-visuals/lua/entity_visuals.lua')
local J=dofile('work/minecraft-fusion/package/PalCraftClient/Scripts/json.lua')
local root='work/minecraft-fusion/entity-visuals/assets/'
E.configure({root=root,json=J})
local f=assert(io.open(root..'vanilla-pose-samples.json'));local samples=J.decode(f:read('*a'));f:close()
local cases=0;local maxPose,maxVertex,maxNormal=0,0,0
for _,sample in ipairs(samples)do
 local rig=assert(E.rig(sample.kind));local poses=E.pose(rig,sample.state)
 for id,expected in pairs(sample.poses)do for i,v in ipairs(expected)do
  -- MC Mth uses a float sine lookup; Lua's analytic trig differs below a texel.
  local error=math.abs(poses[id][i]-v);maxPose=math.max(maxPose,error);assert(error<.0002,sample.kind..' '..sample.name..' '..id..' pose '..i..' error '..error)
 end end
 -- Compare the actual original model output before renderer-only effects.
 local state={};for k,v in pairs(sample.state)do state[k]=v end
 state.death_time=0;state.swelling=0
 local groups=assert(E.geometry(sample.kind,state));local g=groups[1]
 local byPart={}
 for _,face in ipairs(sample.faces)do byPart[face.part]=byPart[face.part]or{};table.insert(byPart[face.part],face)end
 local faceCounts={}
 for _,range in ipairs(g.face_ranges)do
  local part=range.part;faceCounts[part]=(faceCounts[part]or 0)+1
  local face=byPart[part][faceCounts[part]]
  for i,v in ipairs(face.vertices)do
   local actual=g.vertices[range.first_vertex+i]
   local expected={-v[3]*100,v[1]*100,(1.501-v[2])*100,-v[6],v[4],-v[5],v[7],v[8]}
   for k=1,8 do
    local error=math.abs(actual[k]-expected[k]);if k<=3 then maxVertex=math.max(maxVertex,error)elseif k<=6 then maxNormal=math.max(maxNormal,error)end
    assert(error<(k<=3 and .02 or .0002),sample.kind..' '..sample.name..' '..part..' vertex '..k..' error '..error)
   end
  end
 end
 cases=cases+1
end
local _,death=E.geometry('zombie',{death_time=10})
assert(math.abs(death.death_roll-math.sqrt(9/20*1.6)*math.pi/2)<1e-10)
assert(death.red_overlay)
local _,flash=E.geometry('creeper',{swelling=.55})
assert(flash.white_overlay==.55 and flash.scale_xz~=1 and flash.scale_y~=1)
local result={status='passed',cases=cases,max_pose_error=maxPose,max_vertex_error_cm=maxVertex,max_normal_error=maxNormal,
 source='Actual MC26.3 model setupAnim/ModelPart.visit',night_low_power=true,runtime_graphics_verified=false}
local out=assert(io.open('work/minecraft-fusion/entity-visuals/verification.json','wb'));out:write(J.encode(result));out:close();print(J.encode(result))
