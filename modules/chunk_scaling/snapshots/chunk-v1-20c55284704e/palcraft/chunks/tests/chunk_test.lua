local T=dofile('/path/to/workspace/work/minecraft-fusion/palcraft/chunks/tests/support.lua')
local G=T.G;local checks=0;local cases={}
local function check(v,msg)checks=checks+1;assert(v,msg)end
local function case(name,fn)
 if arg[1]and not(','..arg[1]..','):find(','..name..',',1,true)then return end
 fn();cases[#cases+1]=name
end
local function packet(s)local out;for _,c in pairs(s.chunks)do out=c.packet end;return assert(out)end
case('original_quads_uv_normals_winding',function()
 local b=T.block(0,64,0,'oak_stairs','facing=east,half=bottom,shape=inner_left,waterlogged=false',{{0,0,0,1,.5,1},{0,.5,0,.5,1,1},{.5,.5,.5,1,1,1}})
 local original=T.geometry.geometry(b.id,b.state,0,64,0);local original_digest=G.stable(original)
 local s=T.scheduler();s:apply_blocks(nil,{b});T.drain(s);local p=packet(s)
 local groups=p.visual_pages[1].groups;check(#groups==#original,'Same material sections')
 for i,g in ipairs(groups)do
  check(#g.vertices==#original[i].vertices and #g.indices==#original[i].indices,'Original topology')
  for j,v in ipairs(g.vertices)do for k=1,8 do check(v[k]==original[i].vertices[j][k],'Original cm/normal/UV retained')end end
  for j,index in ipairs(g.indices)do check(index==original[i].indices[j],'Oracle winding retained')end
 end
 check(G.stable(original)==original_digest,'Cached geometry remains immutable')
end)
case('adjacency_and_partial_face_shape_union',function()
 check(G.covered({{0,0,1,1}},{{0,0,.5,1},{.5,0,1,1}}),'Exact rectangle union')
 check(not G.covered({{0,0,1,1}},{{0,0,.49,1},{.5,0,1,1}}),'No epsilon-sized hole inflation')
 local a,b=T.block(0,64,0),T.block(1,64,0);a.occlusion=T.full_occlusion;b.occlusion=T.full_occlusion
 local s=T.scheduler();s:apply_blocks(nil,{a,b});T.drain(s);check(packet(s).stats.faces==10 and packet(s).stats.culled_faces==2,'Two shared cube faces culled')
 local glass=T.block(1,64,0,'glass');s:apply_blocks(nil,{glass});T.drain(s);check(packet(s).stats.faces==12,'Unknown/translucent occlusion retained')
 a.face_visibility={east=false};s:apply_blocks(nil,{a});T.drain(s);check(packet(s).stats.faces==11,'Authoritative MC shouldRenderFace respected')
end)
case('metadata_alpha_tint_animation_and_dynamic_fallback',function()
 local leaves=T.block(0,64,0,'oak_leaves','persistent=true,distance=7,waterlogged=false');leaves.tint_values={['0']={.2,.6,.1}}
 local chest=T.block(1,64,0,'chest','facing=north,type=single,waterlogged=false');chest.block_entity={lid=.4,items={{slot=0,id='minecraft:stone',count=2}}}
 local water=T.block(2,64,0,'water','level=0',{});water.fluid={id='minecraft:water',source=true,height=1,flow={0,0,0},collision='ignore',simulation='minecraft'}
 local animation=T.block(3,64,0,'magma_block')
 local s=T.scheduler();s:apply_blocks(nil,{leaves,chest,water,animation});T.drain(s);local p=packet(s)
 check(#p.dynamic==1 and p.dynamic[1].block.block_entity.lid==.4,'Chest parts and state retained for dynamic adapter')
 check(#p.fluids==1 and p.fluids[1].fluid.height==1,'Actual fluid preserved separately')
 check(#p.fallbacks==1 and p.fallbacks[1].reason=='special_model_required','Unbaked fluid explicit fallback')
 check(p.requirements.tint and p.requirements.animation and p.requirements.dynamic,'Capabilities required explicitly')
 local found=false
 for _,page in ipairs(p.visual_pages)do for _,g in ipairs(page.groups)do if g.texture=='minecraft:block/oak_leaves'then
  found=true;check(g.alpha_mode=='cutout'and g.tint==0 and g.tint_value[2]==.6,'Cutout biome tint retained')
 end end end;check(found,'Leaves batched without metadata loss')
end)
case('native_page_caps_and_zero_based_indices',function()
 local s=T.scheduler({page_vertices=48,page_indices=72,page_sections=2});local bs={}
 for x=0,9 do bs[#bs+1]=T.block(x,64,0,'crafting_table')end
 s:apply_blocks(nil,bs);T.drain(s);check(#packet(s).visual_pages>1,'Multiple capped native pages')
 for _,page in ipairs(packet(s).visual_pages)do
  check(page.vertices<=48 and page.indices<=72 and #page.groups<=2,'Native hard limits')
  for _,g in ipairs(page.groups)do for _,i in ipairs(g.indices)do check(i>=0 and i<#g.vertices,'Each section has local zero indices')end end
 end
end)
case('dirty_tile_cross_chunk_and_cancellation',function()
 local s,a=T.scheduler({page_vertices=32});local bs={}
 for x=0,19 do for z=0,5 do bs[#bs+1]=T.block(x,64,z)end end
 s:apply_blocks(nil,bs);T.drain(s);local commits=a.commits;local built=s.stats.tiles_built
 s:apply_blocks(nil,{T.block(15,64,2,'stone')});T.drain(s)
 check(a.commits-commits==2,'Boundary edit updates both chunks')
 check(s.stats.tiles_built-built<=4,'Only neighboring dirty tiles rebuilt')
 local stable=T.digest(s);s:apply_blocks(nil,{T.block(1,64,1,'stone')})
 for _=1,10000 do s:tick(20,1);local prepared=false;for _,c in pairs(s.chunks)do if c.job and #c.job.prepared.visual>0 then prepared=true end end;if prepared then break end end
 local discarded=a.discarded;s:apply_blocks(nil,{T.block(1,64,1,'oak_planks')});T.drain(s)
 check(a.discarded>discarded,'In-flight native pages discarded on stale revision')
 check(T.digest(s)==stable,'Cancelled work never publishes stale data')
end)
case('atomic_failure_keeps_previous_and_retry',function()
 local s,a=T.scheduler();s:apply_blocks(nil,{T.block(0,64,0)});T.drain(s);local old=packet(s);local retained=a.count()
 a.fail_commit=true;s:apply_blocks(nil,{T.block(0,64,0,'stone')})
 while s:status().pending>0 do s:tick(2,128)end
 check(next(s.errors)~=nil and packet(s)==old,'Rejected transaction keeps old revision')
 check(a.count()==retained,'Rejected transaction cleans staging handles')
 a.fail_commit=false;s:retry();T.drain(s);check(packet(s)~=old,'Retry commits exact latest state')
end)
case('collision_union_preserves_stairs_fence_holes_and_water_channels',function()
 local records={};local originals={{0,0,0,1,.5,1},{0,.5,0,.5,1,1},{1,0,0,2,.5,1},{1.375,.5,.375,1.625,1.5,.625}}
 for _,b in ipairs(originals)do records[#records+1]={bounds=b,properties={policy=G.collision_policy}}end
 local merged=G.merge_boxes(records)
 local function contains(boxes,x,y,z,records)
  for _,v in ipairs(boxes)do local b=records and v.bounds or v;if x>b[1]and x<b[4]and y>b[2]and y<b[5]and z>b[3]and z<b[6]then return true end end;return false
 end
 for x=.025,1.975,.05 do for y=.025,1.475,.05 do for z=.025,.975,.05 do check(contains(originals,x,y,z)==contains(merged,x,y,z,true),'Exact occupancy union')end end end
 check(#merged<#originals,'Adjacent boxes merged')
 for _,channel in ipairs({14,19,25})do local has=false;for _,c in ipairs(G.collision_policy.ignore_channels)do if c==channel then has=true end end;check(has,'Water channels ignore')end
end)
case('v2_snapshot_cancel_replace_late_delta_and_global_seq',function()
 local s=T.scheduler();s:apply_blocks(nil,{T.block(0,64,0),T.block(1,64,0)});T.drain(s);local before=T.digest(s)
 local function ingest(seq,lifecycle,ops)return s:ingest({t='blocks',v=2,session='test-session',seq=seq,dim='minecraft:overworld',lifecycle=lifecycle,ops=ops or{}})end
 local bounds={0,64,0,16,80,16}
 ingest(1,{{op='snapshot_begin',snapshot='cancel',bounds=bounds}})
 local b=T.block(0,64,0,'stone');b.op='upsert';b.snapshot='cancel';ingest(2,{}, {b})
 check(T.digest(s)==before,'Snapshot pages remain unpublished')
 ingest(3,{{op='snapshot_cancel',snapshot='cancel'}});check(T.digest(s)==before,'Cancelled snapshot preserves old set')
 ingest(4,{{op='snapshot_begin',snapshot='complete',bounds=bounds}})
 b.snapshot='complete';ingest(5,{}, {b})
 local newer=T.block(0,64,0,'glass');newer.op='upsert';ingest(6,{}, {newer})
 ingest(7,{{op='snapshot_end',snapshot='complete',bounds=bounds}});T.drain(s)
 check(s:status().blocks==1 and s:get('minecraft:overworld',0,64,0).id=='minecraft:glass','Complete bounds replace and later delta wins')
 check(not ingest(6,{}, {b}),'Stale global sequence rejected')
 check(s:get('minecraft:overworld',0,64,0).id=='minecraft:glass','Stale row cannot overwrite')
end)
case('unload_reconnect_and_dimension_separation',function()
 local s,a=T.scheduler({origins={['minecraft:the_nether']={X=10000,Y=20000,Z=30000}}})
 local bs={T.block(-1,64,-1),T.block(16,64,0)};s:apply_blocks(nil,bs);s:apply_blocks('minecraft:the_nether',bs);T.drain(s)
 check(s:status().sections==4,'Negative coordinates and dimensions separated')
 local digest=T.digest(s);s:reconnect(true);T.drain(s);check(T.digest(s)==digest,'Reconnect rebuild is geometrically identical')
 local n=a.count();s:unload('minecraft:overworld',-1,nil,-1);T.drain(s);check(a.count()<n and s:status().blocks==3,'Unload removes only selected dimension column')
 s:reset('new-session',false,false);check(a.count()==0 and s:status().blocks==0,'Travel abandons all stale handles')
end)
case('capability_rejection_has_no_silent_visual_degradation',function()
 local s,a=T.scheduler();a.capabilities.translucent=false;s:apply_blocks(nil,{T.block(0,64,0,'glass')})
 while s:status().pending>0 do s:tick(2,128)end
 check(a.count()==0 and next(s.errors)~=nil,'Unsupported glass fails before native publication')
 a.capabilities.translucent=true;s:retry();T.drain(s);check(a.count()>0,'Capability upgrade resumes same geometry')
end)
case('view_readiness_air_coverage_regions_and_fencing',function()
 local s,a=T.scheduler();local dim='minecraft:the_nether';local bounds={-64,0,-64,64,128,64}
 local mapping={region_id='nether-page0',world_session='test-session',dim=dim,origin={X=100000,Y=200000,Z=300000},mc_anchor={0,64,0},scale=100,y_origin=64}
 local ticket=s:prepare_view({player='p',world_session='test-session',dim=dim,view='v',mapping=mapping,required_bounds=bounds,mode='server'})
 check(not s:readiness(ticket).ready and s:readiness(ticket).visual_pending==0,'Empty queue is not coverage; server needs no visual')
 s:ingest({session='test-session',seq=1,dim=dim,ops={},lifecycle={{op='snapshot_begin',snapshot='air',bounds=bounds,player='p'}}})
 check(not s:readiness(ticket).ready,'Incomplete air snapshot not ready')
 s:ingest({session='test-session',seq=2,dim=dim,ops={},lifecycle={{op='snapshot_end',snapshot='air',bounds=bounds,player='p'}}})
 check(s:readiness(ticket).ready and s:readiness(ticket).coverage_complete,'Complete all-air snapshot proves coverage')
 a.capabilities.collision_verified=false;check(not s:readiness(ticket).ready,'Offline collider cannot claim runtime readiness');a.capabilities.collision_verified=true
 s:activate(ticket)
 local ticket2=s:prepare_view({player='q',world_session='test-session',dim=dim,view='v2',mapping=mapping,required_bounds=bounds,mode='server'})
 s:release(ticket);check(s.regions[mapping.region_id].refs==1,'Release preserves other player region reference')
 s:reconnect(false);check(not s:readiness(ticket2).ready,'Generation fences old tickets')
end)
case('lua_native_wire_fixture',function()
 local C=dofile(T.root..'palcraft/client/chunk_collision.lua');local pointers={}
 for i=1,19 do pointers[i]=0x10000+i*0x100 end
 local bytes=C.encode(pointers,{120,-250,300},7,1,0,{{0,-100,0,100,0,100},{100,-100,0,200,0,50}},{},{})
 check(#bytes==216+2*48 and bytes:sub(1,8)=='PALCCOL1','Lua produces exact native wire')
 local f=assert(io.open(T.root..'chunk_scaling/lua-collision-fixture.bin','wb'));f:write(bytes);f:close()
end)
case('snapshot_semantic_coalescing_and_atomic_validation',function()
 local s=T.scheduler({max_snapshot_blocks=1});s:apply_blocks(nil,{T.block(0,64,0)});T.drain(s);local commits=s.stats.commits
 local bounds={0,64,0,16,80,16};local b=T.block(0,64,0);b.op='upsert';b.snapshot='same';b.tick=100;b.flags=1;b.causes={'snapshot'}
 s:ingest({seq=1,lifecycle={{op='snapshot_begin',snapshot='same',bounds=bounds}},ops={b}})
 s:ingest({seq=2,lifecycle={{op='snapshot_end',snapshot='same',bounds=bounds}},ops={}});T.drain(s)
 check(s.stats.commits==commits,'Unchanged snapshot envelope does not rebuild geometry')
 s:ingest({seq=3,lifecycle={{op='snapshot_begin',snapshot='full',bounds=bounds}},ops={}})
 local c=T.block(1,64,0);c.op='upsert';c.snapshot='full';b.snapshot='full'
 local ok=pcall(s.ingest,s,{seq=4,ops={{op='remove',at={0,64,0}},b,c}})
 check(not ok and s:status().blocks==1 and s.snapshots.full.count==0,'Capacity failure mutates no live or snapshot data')
 ok=pcall(s.ingest,s,{session='bad-new-session',seq=1,ops={{op='upsert',id='minecraft:stone',at={0.1,64,0}}}})
 check(not ok and s.session=='test-session'and s:status().blocks==1,'Malformed new session cannot delete old world')
end)
case('multiple_region_nonempty_tickets_and_mapping_fence',function()
 local s,a=T.scheduler();local dim='minecraft:the_end'
 local function req(id,x,origin,view)
  return{world_session='test-session',dim=dim,view=view,player='p',mode='client',required_bounds={x,64,0,x+16,80,16},
   mapping={region_id=id,dim=dim,world_session='test-session',origin={X=origin,Y=0,Z=500000},mc_anchor={x,64,0},scale=100,y_origin=64}}
 end
 local t1=s:prepare_view(req('r1',0,100000,10));local t2=s:prepare_view(req('r2',256,200000,11))
 local b1,b2=T.block(0,64,0),T.block(256,64,0);b1.op='upsert';b1.snapshot='s1';b2.op='upsert';b2.snapshot='s2'
 s:ingest({seq=1,dim=dim,lifecycle={{op='snapshot_begin',snapshot='s1',bounds=t1.required_bounds},{op='snapshot_begin',snapshot='s2',bounds=t2.required_bounds}},ops={b1,b2}})
 s:ingest({seq=2,dim=dim,lifecycle={{op='snapshot_end',snapshot='s1',bounds=t1.required_bounds},{op='snapshot_end',snapshot='s2',bounds=t2.required_bounds}},ops={}})
 check(not s:readiness(t1).ready and s:readiness(t1).collision_pending>0,'Snapshot alone does not prove registered collider')
 T.drain(s);check(s:readiness(t1).ready and s:readiness(t2).ready,'Both different pages become independently ready')
 local regions={};for _,c in pairs(s.chunks)do regions[c.packet.region_id]=c.packet.fence end
 check(regions.r1.mapping=='r1'and regions.r2.mapping=='r2'and regions.r1.view==10,'Explicit page mapping/view fences')
 s:release(t1);T.drain(s);check(s:readiness(t2).ready and s:status().blocks==1,'Releasing old page preserves other committed page')
 s:prepare_view(req('r3',512,300000,12));s:prepare_view(req('r4',768,400000,13));s:prepare_view(req('r5',1024,500000,14))
 check(not pcall(s.prepare_view,s,req('r6',1280,600000,15)),'Capacity exhaustion fails explicitly')
 check(not pcall(s.prepare_view,s,req('r2',256,700000,99)),'Cannot replace mapping while referenced')
end)
case('overlapping_halo_regions_have_independent_native_instances',function()
 local V=dofile(T.root..'palcraft/client/chunk_views.lua');local a=T.adapter()
 local v=V.new({geometry=T.geometry,adapter=a,session='test-session',frame_budget_ms=2,frame_steps=128})
 local dim='minecraft:the_nether'
 local function request(id,anchor,center,x,view)
  return{world_session='test-session',dim=dim,view=view,player='p',mode='client',session_generation=99,
   mapping={region_id=id,world_session='test-session',dim=dim,origin={X=center-anchor*100,Y=0,Z=500000},
    mc_anchor={anchor,64,0},scale=100,y_origin=64,page_size=512,window_size=656,
    region_bounds={center-32768,-32768,500000-32768,center+32768,32768,500000+32768}},required_bounds={x-64,64,-64,x+64,80,64}}
 end
 local one=v:prepare_view(request('halo1',0,0,250,1));local two=v:prepare_view(request('halo2',512,100000,260,2))
 local b=T.block(250,64,0);b.op='upsert';b.snapshot='halo'
 local bounds={180,64,-64,328,80,64}
 v:ingest({seq=1,session='test-session',dim=dim,lifecycle={{op='snapshot_begin',snapshot='halo',bounds=bounds}},ops={b}})
 v:ingest({seq=2,session='test-session',dim=dim,lifecycle={{op='snapshot_end',snapshot='halo',bounds=bounds}},ops={}})
 local iterations=0;while v:status().pending>0 do iterations=iterations+1;check(iterations<10000,'Views drain');v:tick(2,128)end
 check(v:readiness(one).ready and v:readiness(two).ready,'Full64 ring prepared on both canonical page edges')
 check(v:readiness(one).session_generation==99 and v:readiness(one).renderer_generation==1,'Outer and renderer generation are independent')
 check(v:readiness(one).collision_committed and v:readiness(one).visual_committed and #v:readiness(one).covered_bounds==6,'Strict travel proof returned')
 check(v:status().blocks==2 and a.count()==4,'Same MC cell has distinct visual/collider instance in each arena')
 local actor1,actor2
 for _,c in pairs(one.region.scheduler.chunks)do actor1=c.active.visual[1].actor end
 for _,c in pairs(two.region.scheduler.chunks)do actor2=c.active.visual[1].actor end
 check(actor1~=actor2,'Halo never picks an arbitrary shared origin')
 v:activate(one);v:release(one);while v:status().pending>0 do v:tick(2,128)end
 check(v:readiness(two).ready and a.count()==2 and v:status().regions==1,'Last old-region reference unloads only its instances')
 v:reset('fresh-world',false,false);check(a.count()==0 and not v:readiness(two).ready,'World reset fences all regions once')
end)
case('json_null_metadata_preserves_static_and_animated_semantics',function()
 check(G.clone(T.J.null)==T.J.null and G.stable(T.J.null)=='n','JSON null sentinel is preserved')
 local wood=T.block(0,64,0);wood.fluid=T.J.null;wood.block_entity=T.J.null
 local s=T.scheduler();s:apply_blocks(nil,{wood});T.drain(s);local p=packet(s)
 check(not p.requirements.animation and #p.dynamic==0 and #p.fluids==0,'Null metadata creates no animation/fluid/dynamic work')
 local nullbox=T.block(1,64,0);nullbox.boxes=T.J.null
 s:apply_blocks(nil,{nullbox});T.drain(s);check(#packet(s).fallbacks==1 and packet(s).fallbacks[1].reason=='missing_collision_shape','Null collision is unknown, never an empty solid shape')
 s:apply_blocks(nil,{T.block(2,64,0,'magma_block')});T.drain(s)
 check(packet(s).requirements.animation,'Real animation descriptor remains required')
end)
local result={status='passed',checks=checks,cases=cases,asset_root=T.asset_root,asset_sha256='7342e9820b46e04a6a4682f7922772de9343987e07ffd9981c97edf66caf6254',native_runtime_verified=false}
T.write(arg[2]or(arg[1]and'chunk-tests-targeted.json'or'chunk-tests.json'),result);print(T.J.encode(result))
