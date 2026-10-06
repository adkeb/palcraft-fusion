-- Small offline regression of sparse coroutine boundaries; no assets/game/DLL.
local dir=assert(arg[1],'Proposal directory required'):gsub('/$','')..'/'
local J=dofile(arg[2] or 'palcraft/client/json.lua')
local oldG=dofile(dir..'baseline/chunk_geometry.lua')
local newG=dofile(dir..'chunk_geometry.lua')
local oldS=dofile(dir..'baseline/chunk_scheduler.lua')
local newS=dofile(dir..'chunk_scheduler.lua')
local checks=0
local function check(ok,why)assert(ok,why);checks=checks+1 end
local dim='minecraft:overworld'
local blocks={{id='test:slab',at={1,64,1},boxes={{0,0,0,1,.5,1}},chunk_visual='static',
 fluid={kind='water',empty=false,height=.4}},
 {id='test:stairs',at={3,64,2},boxes={{0,0,0,1,.5,1},{.5,.5,0,1,1,1}},chunk_visual='static'}}
local geometry={geometry=function()
 return{{texture='test:original',tint=0,tint_rgb=0x77aa33,vertices={
  {0,50,0,0,1,0,0,0},{100,50,0,0,1,0,1,0},
  {100,50,100,0,1,0,1,1},{0,50,100,0,1,0,0,1}},
  indices={0,1,2,0,2,3},face_ranges={{cull='up',first_vertex=0}}}}
end}
local function lookup(_,x,y,z)
 for _,b in ipairs(blocks)do if b.at[1]==x and b.at[2]==y and b.at[3]==z then return b end end
end
local function tile(G)
 local co=coroutine.create(function()return G.build_tile({geometry=geometry},{at={0,64,0},dimension=dim},0,lookup)end)
 local n,result=0
 while coroutine.status(co)~='dead'do
  local ok,v=coroutine.resume(co);assert(ok,v)
  if coroutine.status(co)=='dead'then result=v else n=n+1 end
 end
 return result,n
end
local oldTile,oldYields=tile(oldG);local newTile,newYields=tile(newG)
check(newG.stable(oldTile)==newG.stable(newTile),'Original quads/tint/fluid/exact stair boxes stay identical')
check(oldYields==64 and newYields==2,'Air cells no longer consume individual resumes')
local cap={atomic_commit=true,collision_compound=true,fluids=true,tint=true,alpha_modes={opaque=true}}
local function make(S)
 local commits,discarded={},0
 local a={capabilities=cap,prepare=function(_,_,p)return{page=p}end,
  prepare_collision=function(_,_,p)return{page=p}end,prepare_special=function(_,_,kind,b)return{kind=kind,value=b}end,
  commit=function(fresh,old,p)commits[#commits+1]=newG.clone(p);return fresh end,
  discard=function()discarded=discarded+1 end,unload=function()end}
 local s=S.new({geometry=geometry,adapter=a,context=1,session='offline-sparse',clock=function()return 0 end})
 return s,commits,function()return discarded end
end
local function finish(s)
 local total,frames=0,0
 while s.head<=s.tail do
  frames=frames+1;assert(frames<=20,'Tiny fixture must complete')
  local t=s:tick(2,128);check(t.steps<=128,'Original per-frame step cap remains');total=total+t.steps
 end
 return total,frames
end
local old,oldCommits=make(oldS);local new,newCommits=make(newS)
old:apply_blocks(dim,blocks);new:apply_blocks(dim,blocks)
local oldSteps,oldFrames=finish(old);local newSteps,newFrames=finish(new)
check(#oldCommits==1 and #newCommits==1 and newG.stable(oldCommits[1])==newG.stable(newCommits[1]),'Real Scheduler packet and one atomic commit stay identical')
check(newSteps<oldSteps and newFrames<=oldFrames,'Sparse work needs fewer bounded steps')
-- A full empty section still pauses after each 4^3 scan, rather than scanning
-- all 64 tiles in a single resume after the occupied-block yield is removed.
local empty=newS.new({geometry=geometry,adapter={},session='offline-empty'})
local ch=empty:_chunk(dim,0,64,0,true);ch.revision=1
for i=0,63 do ch.dirty[i]=true end
local queries=0;function empty:get()queries=queries+1;return nil end
local job=empty:_new_job(ch);local maxQueries,tileYields=0,0
while coroutine.status(job.co)~='dead'do
 local before=queries;local ok,label=coroutine.resume(job.co);assert(ok,label)
 maxQueries=math.max(maxQueries,queries-before)
 if label=='tile_build'then tileYields=tileYields+1 end
end
check(tileYields==64 and maxQueries==64 and queries==4096,'Every empty scan has the original 4^3 tile boundary')
-- A revision arriving during build must cancel the old coroutine normally.
local stale,staleCommits,discarded=make(newS);stale:apply_blocks(dim,blocks);stale:tick(2,1)
local changed=newG.clone(blocks[1]);changed.boxes={{0,0,0,1,.25,1}}
stale:apply_blocks(dim,{changed});finish(stale)
check(stale.stats.cancelled_jobs==1 and discarded()==0 and #staleCommits==1 and staleCommits[1].revision==2,'Stale unprepared build is cancelled without native cleanup and only latest revision commits')
check(stale:status().pending==0 and next(stale.errors)==nil,'Normal queue drains without hidden errors')
local report={status='passed',checks=checks,scope='one sparse two-block tile plus bounded empty-section and stale revision checks',
 old_tile_yields=oldYields,new_tile_yields=newYields,old_scheduler_steps=oldSteps,new_scheduler_steps=newSteps,
 old_bounded_frames=oldFrames,new_bounded_frames=newFrames,max_empty_lookups_per_resume=maxQueries,
 simulated_adapter_and_clock=true,actual_runtime_stall_fixed=false,game_or_RPC_or_DLL_calls=false,power_mode='night_low_power'}
local f=assert(io.open(dir..'sparse-yield-tests.json','wb'));f:write(J.encode(report));f:close();print(J.encode(report))
