local C=dofile('work/minecraft-fusion/entity-visuals/lua/captured_entity_visuals.lua')
local J=dofile('work/minecraft-fusion/package/PalCraftClient/Scripts/json.lua')
local ROOT='work/minecraft-fusion/entity-visuals/capture-assets/'
C.configure({root=ROOT,json=J})
local f=assert(io.open(ROOT..'frames.json'));local frames=J.decode(f:read('*a'));f:close()
local maxError=0;local vertexCount=0
for _,frame in ipairs(frames)do
 assert(frame.source=='actual_entity_renderer_submit'and next(frame.unsupported_submissions)==nil)
 local groups,effects=assert(C.capture(frame))
 assert(effects.actor_yaw==0 and effects.world_orientation_baked)
 assert(#groups==#frame.batches)
 for i,g in ipairs(groups)do
  assert(g.collision==false and g.actual_renderer_capture and #g.indices==#g.vertices/4*6)
  for j,actual in ipairs(g.vertices)do
   local v=frame.batches[i].vertices[j];local expected={v[1]*100,-v[3]*100,v[2]*100,v[4],-v[6],v[5],v[7],v[8]}
   for k=1,8 do maxError=math.max(maxError,math.abs(actual[k]-expected[k]))end
  end
  vertexCount=vertexCount+#g.vertices
 end
end
assert(frames[1].renderer:find('CreeperRenderer',1,true))
assert(frames[2].renderer:find('EnderDragonRenderer',1,true)and #frames[2].batches==2)
assert(frames[2].batches[1].textures.Sampler0:find('enderdragon/dragon.png',1,true))
local result={status='passed',actual_renderer_cases=#frames,captured_vertices=vertexCount,max_UE_projection_error=maxError,
 complex_entity='actual EnderDragonRenderer/EnderDragonModel with body+eyes resources',
 kind_whitelist=false,night_low_power=true,runtime_graphics_verified=false}
local out=assert(io.open('work/minecraft-fusion/entity-visuals/verification-capture.json','wb'));out:write(J.encode(result));out:close();print(J.encode(result))
