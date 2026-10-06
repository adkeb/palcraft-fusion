-- One narrow regression: an implemented but unaccepted backend can be composed
-- for the Lab, while native acceptance flags remain false. No game/DLL is invoked.
local T=dofile('/path/to/workspace/work/minecraft-fusion/palcraft/chunks/tests/support.lua')
local World=dofile(T.root..'palcraft/server/world_compat.lua');local installed
local companion={world=World.new({dimension='minecraft:overworld'}),actors={},origin={X=1,Y=2,Z=3}}
companion.world.session='lab-world'
companion.install_consumer=function(binding)installed=binding;return true end
companion.retire_legacy=function()return{ok=true}end
companion.render_signature=T.G.stable;companion.geometry_signature=T.G.stable
local called=0;local models={capabilities={opaque=true}}
models.prepare=function()called=called+1;error('No native operation expected in constructor')end
models.commit_transaction=function()called=called+1;return true end
models.discard=function()end;models.unload=function()end
local collision={prepare=function()called=called+1 end,preflight=function()end,commit=function()end,unload=function()end,discard=function()end,reset=function()end}
local options={client_dir=T.root..'palcraft/client/',companion=companion,models=models,geometry=T.geometry,collision=collision,json=T.J,
 context=function()return{}end,world_session='lab-world',visuals=true,collision_verified=false,visual_verified=false,
 initial_view={world_session='lab-world',dim='minecraft:overworld',view=1,required_bounds={0,64,0,16,80,16},
  mapping={region_id='home',dim='minecraft:overworld',world_session='lab-world',origin=companion.origin,mc_anchor={0,64,0},window_size=656,page_size=512}}}
local runtime=dofile(T.root..'palcraft/runtime/chunks.lua');local api=runtime.new(options);local s=api.status()
assert(installed==api.bridge.binding and s.installed,'The real wrapper must install the actual companion binding')
assert(api.adapter.capabilities.collision_compound,'Implemented compound ABI remains runnable without past QA')
assert(s.acceptance.collision_verified==false and s.acceptance.visual_verified==false,'No acceptance evidence may be fabricated')
api.tick();assert(called==0 and api.companion_driven,'Runtime observer tick must not add a second native driver')
assert(not api.view.readiness(api.initial_ticket).ready,'Missing snapshot and native commit still fail readiness')
local invalid={};for k,v in pairs(options)do invalid[k]=v end;invalid.collision={prepare=function()end}
assert(not pcall(runtime.new,invalid),'Missing real collision transaction ABI still rejects construction')
local result={status='passed',checks=6,scope='unaccepted implemented Lab backend constructor',collision_verified=false,visual_verified=false,
 native_operations=called,graphics=false,power_mode='night_low_power',real_wrapper=true}
T.write('unverified-lab-entry-tests.json',result);print(T.J.encode(result))
