-- Proof fields only: real Scheduler state with synthetic coverage/adapter/clock.
local dir=assert(arg[1]):gsub('/$','')..'/'
local base=assert(arg[2]):gsub('/$','')..'/'
local J=dofile(arg[3] or 'palcraft/client/json.lua')
local G=dofile(dir..'chunk_geometry.lua')
local S=dofile(dir..'chunk_scheduler.lua');local Old=dofile(base..'chunk_scheduler.lua')
local checks=0;local function check(v,why)assert(v,why);checks=checks+1 end
local dim='minecraft:overworld'
local function make(Module)
 local a={capabilities={atomic_commit=true,collision_compound=true},
  prepare_collision=function(_,_,p)return{page=p}end,commit=function(f)return f end,discard=function()end}
 local s=Module.new({adapter=a,geometry={geometry=function()return{}end},visuals=false,session='offline-detail',clock=function()return 0 end})
 local t=s:prepare_view({dim=dim,world_session='offline-detail',view=2,visual=false,
  required_bounds={0,64,0,80,80,16},mapping={region_id='offline-detail',mc_anchor={0,64,0},origin={X=0,Y=0,Z=0}}})
 s.coverage={{dim=dim,bounds={0,64,0,80,80,16},session='offline-detail',generation=1,source='synthetic_test_fixture'}}
 s:apply_blocks(dim,{{id='test:slab',at={1,64,1},boxes={{0,0,0,1,.5,1}}}})
 return s,t
end
local s,t=make(S);local old,ot=make(Old)
local function without_detail(p)local r=G.clone(p);r.pending_sections=nil;r.pending_sections_truncated=nil;return G.stable(r)end
local p=s:readiness(t)
check(without_detail(p)==G.stable(old:readiness(ot)) and not p.ready,'Original proof gates stay byte-equivalent after stripping additive detail')
local d=p.pending_sections[1]
check(d.phase=='build_init'and d.queued and d.dirty_tiles==1 and d.revision==1 and d.job_revision==nil,'Queued unstarted state is factual')
s:tick(2,1);old:tick(2,1);p=s:readiness(t);d=p.pending_sections[1]
check(d.phase=='build_resume'and d.job_revision==1 and d.last_yield=='block','Actual paused coroutine state is visible')
local change={id='test:slab',at={1,64,1},boxes={{0,0,0,1,.25,1}}}
s:apply_blocks(dim,{change});old:apply_blocks(dim,{change});p=s:readiness(t);d=p.pending_sections[1]
check(d.phase=='stale_discard'and d.revision==2 and d.job_revision==1,'Revision mismatch remains pending and is labelled')
local extra={};for i=1,4 do extra[#extra+1]={id='test:slab',at={i*16+1,64,1},boxes={{0,0,0,1,.5,1}}}end
s:apply_blocks(dim,extra);old:apply_blocks(dim,extra);p=s:readiness(t)
check(p.collision_pending==5 and #p.pending_sections==4 and p.pending_sections_truncated==1,'Proof detail is bounded without changing the full pending count')
check(without_detail(p)==G.stable(old:readiness(ot)) and not p.ready,'Detail never grants readiness')
for _,v in ipairs({s,old})do
 local frames=0;while v.head<=v.tail do frames=frames+1;assert(frames<20);v:tick(2,128)end
end
p=s:readiness(t)
check(p.ready and p.collision_committed and p.pending_sections==nil,'Only completed original transactions grant readiness')
check(without_detail(p)==G.stable(old:readiness(ot)) and p.accepted==false,'QA acceptance and all original completed-proof gates stay identical')
local r={status='passed',checks=checks,scope='additive existing-proof fields only, real Scheduler with synthetic coverage and native adapter',
 max_pending_details=4,original_ready_ACK_identity_generation_gates_changed=false,new_timer_reader_clock_or_native_call=false,
 actual_runtime_stall_fixed=false,game_or_RPC_or_DLL_calls=false,power_mode='night_low_power'}
local f=assert(io.open(dir..'pending-progress-tests.json','wb'));f:write(J.encode(r));f:close();print(J.encode(r))
