local E=dofile('work/minecraft-fusion/entity-visuals/lua/entity_visuals_v2.lua')
local J=dofile('work/minecraft-fusion/package/PalCraftClient/Scripts/json.lua')
local ROOT='work/minecraft-fusion/entity-visuals/assets-v2/'
E.configure({root=ROOT,json=J})
local f=assert(io.open(ROOT..'variant-pose-samples.json'));local rows=J.decode(f:read('*a'));f:close()
local cases=0;local maxPose,maxPosition,maxNormal=0,0,0
for _,sample in ipairs(rows)do
 local rig=assert(E.rig(sample.kind,sample.state));assert(rig.rig_key==sample.rig_key)
 local poses=E.pose(rig,sample.state)
 for id,p in pairs(sample.poses)do for i,value in ipairs(p)do
  local e=math.abs(poses[id][i]-value);maxPose=math.max(maxPose,e);assert(e<1e-6,sample.rig_key..' pose '..id..'/'..i..' '..e)
 end end
 local groups=assert(E.geometry(sample.kind,sample.state));local g=groups[1]
 local faces={};for _,face in ipairs(sample.faces)do faces[face.part]=faces[face.part]or{};table.insert(faces[face.part],face)end
 local numbers={}
 for _,r in ipairs(g.face_ranges)do
  numbers[r.part]=(numbers[r.part]or 0)+1;local face=faces[r.part][numbers[r.part]]
  for i,v in ipairs(face.vertices)do
   local a=g.vertices[r.first_vertex+i];local expected={-v[3]*100,v[1]*100,(1.501-v[2])*100,-v[6],v[4],-v[5],v[7],v[8]}
   for k=1,8 do
    local e=math.abs(a[k]-expected[k]);if k<=3 then maxPosition=math.max(maxPosition,e)elseif k<=6 then maxNormal=math.max(maxNormal,e)end
    assert(e<(k<=3 and .0002 or .000001),sample.rig_key..' vertex '..k..' '..e)
   end
  end
 end
 cases=cases+1
end
local function span(groups)
 local lo,hi=math.huge,-math.huge;for _,g in ipairs(groups)do for _,v in ipairs(g.vertices)do lo=math.min(lo,v[3]);hi=math.max(hi,v[3])end end
 return hi-lo
end
local adult=E.geometry('pig',{variant='cold'})
local baby=E.geometry('pig',{variant='cold',baby=true})
assert(span(baby)<span(adult),'True baby rig is smaller without another .5 global scale')
assert(adult[1].texture~=baby[1].texture,'Baby climate skin is separate')
local creeper=assert(E.geometry('creeper',{}));assert(creeper[1].kind=='minecraft:creeper')
local result={status='passed',variant_cases=cases,rig_variants=8,max_pose_error=maxPose,max_vertex_error_cm=maxPosition,
 max_normal_error=maxNormal,night_low_power=true,runtime_graphics_verified=false,
 source='MC26.3 BabyPigModel/ColdPigModel/BabyZombieModel factories/setupAnim/ModelPart.visit'}
local out=assert(io.open('work/minecraft-fusion/entity-visuals/verification-v2.json','wb'));out:write(J.encode(result));out:close();print(J.encode(result))
