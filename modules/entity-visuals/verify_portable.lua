local V=dofile('work/minecraft-fusion/entity-visuals/lua/portable_visuals.lua')
local O=dofile('work/minecraft-fusion/entity-visuals/lua/portable_observer.lua')
local J=dofile('work/minecraft-fusion/package/PalCraftClient/Scripts/json.lua')
local ROOT='work/minecraft-fusion/entity-visuals/portable-assets/'
V.configure({root=ROOT,json=J})
local f=assert(io.open(ROOT..'projectile-pose-samples.json'));local cases=J.decode(f:read('*a'));f:close()
local count,maxPosition,maxNormal=0,0,0
for _,sample in ipairs(cases)do
 local g=assert(V.projectile({kind='minecraft:'..sample.kind,yaw=sample.yaw,pitch=sample.pitch,shake=sample.shake}))[1]
 local parts={};for _,face in ipairs(sample.faces)do parts[face.part]=parts[face.part]or{};table.insert(parts[face.part],face)end
 local n={}
 for _,range in ipairs(g.face_ranges)do
  n[range.part]=(n[range.part]or 0)+1;local face=parts[range.part][n[range.part]]
  for i,v in ipairs(face.vertices)do
   local actual=g.vertices[range.first_vertex+i];local expected={v[1]*100,-v[3]*100,v[2]*100,v[4],-v[6],v[5],v[7],v[8]}
   for k=1,8 do local e=math.abs(actual[k]-expected[k]);if k<=3 then maxPosition=math.max(maxPosition,e)elseif k<=6 then maxNormal=math.max(maxNormal,e)end
    assert(e<(k<=3 and .0002 or .000002),sample.kind..' actual renderer pose '..k..' error '..e)
   end
  end
 end
 count=count+1
end
local wood=assert(V.item({item='minecraft:oak_log',count=1,age=0,bob_offset=0,render_seed=5}))
local pick=assert(V.item({item='minecraft:iron_pickaxe',count=1,age=0,bob_offset=0,render_seed=5}))[1]
local woodVertices=0;for _,g in ipairs(wood)do woodVertices=woodVertices+#g.vertices;assert(g.collision==false)end
assert(woodVertices==24 and #pick.vertices>24 and pick.collision==false)
local counts={spawn=0,update=0,remove=0,commit=0}
local models={spawn_groups=function()counts.spawn=counts.spawn+1;return counts.spawn end,
 update_groups=function()counts.update=counts.update+1 end,set_actor_pose=function()end,set_visible=function()end,
 release_model=function()counts.remove=counts.remove+1 end}
local observer=O.new({models=models,visuals=V,origin={X=0,Y=0,Z=0},session='lab',dimension='minecraft:overworld',context=function()return 1 end,now=function()return 10 end,
 on_drop_committed=function()counts.commit=counts.commit+1 end})
local snap={t='drops',authority='mc_server',session='lab',epoch='e1',revision=1,unix=10,dimension='minecraft:overworld',items={{uuid='drop-a',item='minecraft:iron_pickaxe',count=1,x=0,y=64,z=0,age=0,bob_offset=0}}}
assert(observer.apply(snap));assert(counts.spawn==1 and counts.commit==1)
snap.revision=2;snap.items[1].age=1;assert(observer.apply(snap));assert(counts.spawn==1 and counts.update==1)
snap.revision=3;snap.items={};assert(observer.apply(snap));assert(counts.remove==1)
local rejected,why=observer.apply({t='drops',unix=10,items={}});assert(not rejected and why=='unbound_authority')
local result={status='passed',actual_projectile_pose_cases=count,max_position_error_cm=maxPosition,max_normal_error=maxNormal,
 item_masks_source='Actual MC ItemModelGenerator',native_in_place_adapter_fixture=counts,night_low_power=true,runtime_graphics_verified=false}
local out=assert(io.open('work/minecraft-fusion/entity-visuals/verification-portable.json','wb'));out:write(J.encode(result));out:close();print(J.encode(result))
