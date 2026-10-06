-- Deliberate offline scale benchmark. It never opens a game/server/RPC connection.
-- Usage after the coordinator resumes scale work: lua chunk_benchmark.lua --run normal
-- The night_low_power profile refuses measurements, preserving the user's quiet mode.
local T=dofile('/path/to/workspace/work/minecraft-fusion/palcraft/chunks/tests/support.lua')
local G,J=T.G,T.J
local mode=arg[2]or'night_low_power'
local fixture_path=arg[3]or(T.root..'world-compat/evidence/vanilla-state-fixtures.json')
local spec={schema=1,counts={1000,10000},power_mode=mode,asset_root=T.asset_root,
 fixture=fixture_path,measurements={'ingest_cpu_ms','generation_cpu_ms','faces','culled_faces','wire_bytes','lua_memory_kib',
 'material_pages','collision_pages','exact_boxes_before_after','dirty_tiles','incremental_commit_count','unload_reconnect_digest'},
 graphics=false,runtime_fps_measured=false,method='frozen original models plus offline MC26.3 shape/shouldRenderFace oracle'}
if arg[1]~='--run'or mode=='night_low_power'then
 spec.status='deferred';spec.reason=mode=='night_low_power'and'user_requested_night_low_power_scale_pause'or'explicit_scale_run_required'
 T.write('benchmark-plan.json',spec);print(J.encode(spec));return
end
local f=assert(io.open(fixture_path,'rb'),'Vanilla collision/visibility fixtures must be ready before benchmarking')
local oracle=J.decode(f:read('*a'));f:close()
assert(oracle.minecraft=='26.3','Vanilla fixture version mismatch')
local samples=assert(oracle.samples);local visibility=assert(oracle.face_visibility_pairs,'Original shouldRenderFace pair oracle required; no collision-derived culling')
local palette={'wood','stone','glass','leaves','slab','stairs','fence'}
for _,name in ipairs(palette)do assert(samples[name]and visibility[name],'Incomplete vanilla palette')end
local function scene(count)
 local width=count==1000 and 10 or 20;local depth=width;local height=count//(width*depth)
 local blocks,by={},{}
 for y=0,height-1 do for z=0,depth-1 do for x=0,width-1 do
  -- A dense support/base volume plus actual slabs, stairs, glass, leaves and posts.
  local pattern=(x*17+z*31+y*13)%20
  local name=pattern<8 and'wood'or pattern<15 and'stone'or palette[pattern-12]
  local b=G.clone(samples[name]);b.at={x,64+y,z};b.op=nil;b.snapshot=nil;b.face_visibility={};b.face_unknown={}
  if name=='leaves'then b.tint_values={['0']={.25,.6,.15}}end -- explicit test-biome input, not a native tint claim
  blocks[#blocks+1]=b;by[G.stable(b.at)]={block=b,palette=name}
 end end end
 for _,b in ipairs(blocks)do local cell=by[G.stable(b.at)]
  for direction,d in pairs(G.directions)do
   local neighbor=by[G.stable({b.at[1]+d[1],b.at[2]+d[2],b.at[3]+d[3]})]
   local visible=assert(visibility[cell.palette][neighbor and neighbor.palette or'air'],'Incomplete visibility oracle')[direction]
   assert(type(visible)=='boolean','Missing original face boolean');b.face_visibility[direction]=visible
  end
 end
 return blocks
end
local function totals(s)
 local out={visual_pages=0,collision_pages=0,static_actor_count=0}
 for _,ch in pairs(s.chunks)do local p=assert(ch.packet)
  for name,n in pairs(p.stats)do out[name]=(out[name]or 0)+n end
  out.visual_pages=out.visual_pages+#p.visual_pages;out.collision_pages=out.collision_pages+#p.collision_pages
 end
 out.static_actor_count=out.visual_pages+out.collision_pages;return out
end
local result={schema=1,status='passed',power_mode=mode,scope='offline_cpu_geometry_and_transaction_counts',
 runtime_fps_measured=false,collision_runtime_verified=false,asset_root=T.asset_root,
 asset_sha256='7342e9820b46e04a6a4682f7922772de9343987e07ffd9981c97edf66caf6254',scenes={}}
for _,count in ipairs({1000,10000})do
 collectgarbage('collect');T.geometry.clear_cache();local initial=collectgarbage('count');local bs=scene(count)
 local s,a=T.scheduler();local t0=os.clock();s:apply_blocks(nil,bs);local t1=os.clock();local peak=collectgarbage('count');local frames=0
 while s:status().pending>0 do frames=frames+1;s:tick(2,128);peak=math.max(peak,collectgarbage('count'))end
 assert(next(s.errors)==nil,G.stable(s.errors));local t2=os.clock();local digest=T.digest(s);local summary=totals(s)
 summary.count=count;summary.ingest_cpu_ms=(t1-t0)*1000;summary.generation_cpu_ms=(t2-t1)*1000;summary.ticks=frames
 summary.lua_memory_kib=collectgarbage('count')-initial;summary.lua_peak_delta_kib=peak-initial
 summary.max_scheduler_tick_cpu_ms=s.stats.max_tick_ms;summary.budget_overruns=s.stats.budget_overruns
 summary.digest=digest;summary.naive_actor_count=count+summary.input_boxes
 local before_commits,before_tiles=s.stats.commits,s.stats.tiles_built
 local edited=G.clone(bs[1]);edited.id='minecraft:crafting_table';edited.state='';edited.properties={};edited.face_visibility=G.clone(bs[1].face_visibility)
 local update_start=os.clock();s:apply_blocks(nil,{edited});T.drain(s)
 summary.incremental_cpu_ms=(os.clock()-update_start)*1000
 summary.incremental_commits=s.stats.commits-before_commits;summary.incremental_tiles=s.stats.tiles_built-before_tiles
 s:apply_blocks(nil,{bs[1]});T.drain(s);assert(T.digest(s)==digest,'Reverting edit must restore exact geometry/collision digest')
 s:reconnect(true);T.drain(s);assert(T.digest(s)==digest,'Reconnect rebuild must be identical')
 local coords={};for _,ch in pairs(s.chunks)do coords[#coords+1]=G.clone(ch.coords)end
 for _,c in ipairs(coords)do s:unload('minecraft:overworld',c[1],c[2],c[3])end;T.drain(s)
 assert(s:status().blocks==0 and a.count()==0,'Unload must retire all mock native handles')
 s:apply_blocks(nil,bs);T.drain(s);assert(T.digest(s)==digest,'Unload then reload must be identical')
 summary.reconnect_consistent=true;summary.unload_reload_consistent=true;summary.actor_unload_leaks=0
 result.scenes[#result.scenes+1]=summary
end
T.write('scale-benchmark.json',result);print(J.encode(result))
