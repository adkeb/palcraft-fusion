local E=dofile('work/minecraft-fusion/entity-visuals/lua/entity_visuals_v3.lua')
local J=dofile('work/minecraft-fusion/package/PalCraftClient/Scripts/json.lua')
local ROOT='work/minecraft-fusion/entity-visuals/assets-v3/'
E.configure({root=ROOT,json=J})
local f=assert(io.open(ROOT..'common-pose-samples.json'));local samples=J.decode(f:read('*a'));f:close()
local maxPose,maxPosition,maxNormal,cases=0,0,0,0
for _,sample in ipairs(samples)do
 local rig=assert(E.rig(sample.kind,sample.state));local poses=E.pose(rig,sample.state)
 for id,p in pairs(sample.poses)do for i,v in ipairs(p)do
  local error=math.abs(poses[id][i]-v);maxPose=math.max(maxPose,error)
  assert(error<1e-6,sample.kind..' '..sample.name..' '..id..'/'..i..' error '..error)
 end end
 local groups=assert(E.geometry_from_rig(rig,sample.state));local g=groups[1]
 local faces={};for _,face in ipairs(sample.faces)do faces[face.part]=faces[face.part]or{};table.insert(faces[face.part],face)end
 local numbers={}
 for _,range in ipairs(g.face_ranges)do
  local id=range.part;numbers[id]=(numbers[id]or 0)+1;local face=faces[id][numbers[id]]
  for i,v in ipairs(face.vertices)do
   local actual=g.vertices[range.first_vertex+i];local expected={-v[3]*100,v[1]*100,(1.501-v[2])*100,-v[6],v[4],-v[5],v[7],v[8]}
   for k=1,8 do
    local e=math.abs(actual[k]-expected[k]);if k<=3 then maxPosition=math.max(maxPosition,e)elseif k<=6 then maxNormal=math.max(maxNormal,e)end
    assert(e<(k<=3 and .00025 or .000001),sample.kind..' '..sample.name..' '..id..' vertex '..k..' error '..e)
   end
  end
 end
 cases=cases+1
end
local wool=assert(E.geometry('sheep',{}));assert(#wool==2 and wool[2].render_layer=='wool')
assert(#E.geometry('sheep',{sheared=true})==1)
local _,death=E.geometry('spider',{death_time=20});assert(math.abs(death.death_roll-math.pi)<1e-9)
local result={status='passed',actual_common_pose_cases=cases,creature_types=6,extra_sheep_wool_layer=true,
 max_pose_error=maxPose,max_vertex_error_cm=maxPosition,max_normal_error=maxNormal,
 night_low_power=true,runtime_graphics_verified=false,source='actual MC model/renderstate export'}
local out=assert(io.open('work/minecraft-fusion/entity-visuals/verification-v3.json','wb'));out:write(J.encode(result));out:close();print(J.encode(result))
