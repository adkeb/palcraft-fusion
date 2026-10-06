-- One tiny source-only check for attribution labels; no game, assets, DLL or
-- benchmark is run. The injected clock simulates a known expensive prepare.
local root='/path/to/workspace/work/minecraft-fusion/'
local S=dofile(root..'palcraft/client/chunk_scheduler.lua')
local J=dofile(root..'package/PalCraftClient/Scripts/json.lua')
local now=0;local prepare_calls=0
local adapter={prepare=function(_,_,page)prepare_calls=prepare_calls+1;now=now+.008;return{actor=1,revision=page.revision}end}
local s=S.new({geometry={},adapter=adapter,clock=function()return now end,session='timing-only'})
local ch=s:_chunk('minecraft:overworld',0,64,0,true);ch.revision=1
ch.job={phase='visual',index=1,revision=1,generation=1,fence={world_session='timing-only',dim='minecraft:overworld',view=0,mapping='home'},
 packet={visual_pages={{at={0,64,0},revision=1,groups={},vertices=4,indices=6}},collision_pages={}},prepared={visual={},collision={},special={}}}
s:_enqueue(ch);local tick=s:tick(2,128);local p=s:status().stats.step_timing
assert(prepare_calls==1 and tick.steps==1,'Budget remains checked after the indivisible native API; no extra work added')
assert(p.peak.phase=='visual_prepare'and p.peak.page_vertices==4 and p.peak.page_indices==6,'Peak identifies actual scheduler boundary and request size')
assert(math.abs(p.peak.elapsed_ms-8)<1e-6 and p.phases.visual_prepare.calls==1,'Same injected clock labels the known cost exactly')
assert(p.peak.origin:find('not a DLL attribution',1,true),'Aggregate prepare must never be labelled as a particular DLL')
local result={status='passed',checks=4,scope='one tiny attribution-source check',simulated_clock=true,real_performance_measured=false,
 game_started=false,native_calls=false,power_mode='night_low_power'}
local f=assert(io.open(root..'chunk_scaling/step-timing-tests.json','wb'));f:write(J.encode(result));f:close();print(J.encode(result))
