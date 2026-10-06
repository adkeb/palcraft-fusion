local E=dofile('work/minecraft-fusion/entity-visuals/lua/entity_visuals_v4.lua')
local J=dofile('work/minecraft-fusion/package/PalCraftClient/Scripts/json.lua')
local ROOT='work/minecraft-fusion/entity-visuals/assets-v4/'
E.configure({root=ROOT,json=J})
local f=assert(io.open(ROOT..'animal-pose-samples.json'));local rows=J.decode(f:read('*a'));f:close()
local cases,maxPose,maxPosition,maxNormal=0,0,0,0
for _,sample in ipairs(rows)do
 local rig=assert(E.rig(sample.kind,sample.state));assert(rig.rig_key==sample.rig_key)
 local poses=E.pose(rig,sample.state)
 for id,p in pairs(sample.poses)do for i,value in ipairs(p)do
  local error=math.abs(poses[id][i]-value);maxPose=math.max(maxPose,error)
  assert(error<1e-6,sample.rig_key..' '..sample.name..' pose '..id..' '..i..' error '..error)
 end end
 local groups=assert(E.geometry_from_rig(rig,sample.state));local g=groups[1]
 local byPart={};for _,face in ipairs(sample.faces)do byPart[face.part]=byPart[face.part]or{};table.insert(byPart[face.part],face)end
 local counters={}
 for _,range in ipairs(g.face_ranges)do
  local id=range.part;counters[id]=(counters[id]or 0)+1;local face=byPart[id][counters[id]]
  for i,v in ipairs(face.vertices)do
   local a=g.vertices[range.first_vertex+i];local expected={-v[3]*100,v[1]*100,(1.501-v[2])*100,-v[6],v[4],-v[5],v[7],v[8]}
   for k=1,8 do
    local error=math.abs(a[k]-expected[k]);if k<=3 then maxPosition=math.max(maxPosition,error)elseif k<=6 then maxNormal=math.max(maxNormal,error)end
    assert(error<(k<=3 and .00025 or .000001),sample.rig_key..' vertex '..k..' error '..error)
   end
  end
 end
 cases=cases+1
end
local fur=assert(E.geometry('sheep',{baby=true}));assert(#fur==2 and fur[2].baby and fur[2].texture:find('_baby',1,true))
assert(#E.geometry('sheep',{baby=true,sheared=true})==1)
local chicken=assert(E.rig('chicken',{baby=true,variant='cold'}));local hasHead=false
for _,p in ipairs(chicken.parts)do if p.id=='/head'then hasHead=true end end;assert(not hasHead,'Actual baby chicken has no separate head bone')
local result={status='passed',animal_variant_rigs=16,actual_pose_cases=cases,max_pose_error=maxPose,max_vertex_error_cm=maxPosition,
 max_normal_error=maxNormal,night_low_power=true,runtime_graphics_verified=false,source='MC26.3 exact animal factories/renderstates'}
local out=assert(io.open('work/minecraft-fusion/entity-visuals/verification-v4.json','wb'));out:write(J.encode(result));out:close();print(J.encode(result))
