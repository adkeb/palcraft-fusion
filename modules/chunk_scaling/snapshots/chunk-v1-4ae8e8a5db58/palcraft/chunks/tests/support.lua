local T={}
T.root='/path/to/workspace/work/minecraft-fusion/'
T.G=dofile(T.root..'palcraft/client/chunk_geometry.lua')
T.S=dofile(T.root..'palcraft/client/chunk_scheduler.lua')
T.J=dofile(T.root..'package/PalCraftClient/Scripts/json.lua')
T.geometry=dofile(T.root..'palcraft/client/model_geometry_v2.lua')
T.asset_root=T.root..'model-compat/snapshots/models-v2-7342e9820b46/'
T.geometry.configure({json=T.J,root=T.asset_root,cache_limit=256})
function T.adapter()
 local a={next=0,live={},commits=0,discarded=0,unloaded=0,
  capabilities={atomic_commit=true,collision_compound=true,fluids=true,dynamic=true,fallbacks=true,tint=true,animation=true,lighting=true,
   opaque=true,cutout=true,translucent=true,visual_verified=true,collision_verified=true}}
 local function prepare(kind,payload)
  a.next=a.next+1;local h={actor=a.next,kind=kind,payload=payload,revision=payload.revision,generation=payload.generation,hidden=true};a.live[h.actor]=h;return h
 end
 function a.prepare(ctx,origin,page)return prepare('visual',page)end
 function a.prepare_collision(ctx,origin,page)return prepare('collision',page)end
 function a.prepare_special(ctx,origin,kind,entry,packet)
  local h=prepare(kind,{revision=packet.revision,generation=packet.generation,entry=entry});return h
 end
 local function retire(set)
  for _,list in pairs(set or{})do for _,h in ipairs(list)do assert(a.live[h.actor]==h,'Unknown mock handle');a.live[h.actor]=nil end end
 end
 function a.commit(fresh,old,packet)
  if a.fail_commit then error('Injected native commit rejection')end
  for _,list in pairs(fresh)do for _,h in ipairs(list)do assert(h.revision==packet.revision and h.generation==packet.generation,'Revision fence');assert(h.hidden,'Prepare publishes nothing')end end
  assert(#fresh.visual==#packet.visual_pages and #fresh.collision==#packet.collision_pages,'Whole chunk transaction')
  retire(old);for _,list in pairs(fresh)do for _,h in ipairs(list)do h.hidden=false end end;a.commits=a.commits+1;return fresh
 end
 function a.discard(h)retire(h);a.discarded=a.discarded+1 end
 function a.unload(h)retire(h);a.unloaded=a.unloaded+1 end
 function a.reset(generation,context_alive)if not context_alive then a.live={}end end
 function a.count()local n=0;for _ in pairs(a.live)do n=n+1 end;return n end
 return a
end
function T.scheduler(extra)
 local a=T.adapter();local opts={geometry=T.geometry,adapter=a,origin={X=120,Y=230,Z=340},tile_size=4,frame_budget_ms=2,frame_steps=128,session='test-session'}
 for k,v in pairs(extra or{})do opts[k]=v end
 return T.S.new(opts),a
end
function T.drain(s,max)
 local ticks=0;local longest=0
 while s:status().pending>0 do
  ticks=ticks+1;assert(ticks<(max or 100000),'Scheduler failed to drain');local r=s:tick(2,128);longest=math.max(longest,r.elapsed_ms)
 end
 assert(next(s.errors)==nil,T.G.stable(s.errors));return ticks,longest
end
function T.block(x,y,z,id,state,boxes)
 return{at={x,y,z},id='minecraft:'..(id or'oak_planks'),state=state or'',boxes=boxes or{{0,0,0,1,1,1}}}
end
T.full_occlusion={can_occlude=true,faces={down=true,up=true,north=true,south=true,west=true,east=true}}
function T.digest(s)
 local h=0xcbf29ce484222325
 local function bytes(str)for i=1,#str do h=(h~str:byte(i))*0x100000001b3 end end
 for _,key in ipairs(T.G.sorted_keys(s.chunks))do local c=s.chunks[key];local p=c.packet
  if p then bytes(key);bytes(T.G.stable(p.at))
   for _,page in ipairs(p.visual_pages)do for _,g in ipairs(page.groups)do
    bytes(g.key);for _,v in ipairs(g.vertices)do bytes(string.pack('<dddddddd',table.unpack(v)))end
    for _,i in ipairs(g.indices)do bytes(string.pack('<I4',i))end
   end end
   for _,page in ipairs(p.collision_pages)do for _,box in ipairs(page.boxes)do bytes(T.G.stable(box))end end
   for _,name in ipairs({'fluids','fallbacks','dynamic'})do bytes(T.G.stable(p[name]))end
  end
 end
 return string.format('%016x',h)
end
function T.write(name,value)
 local f=assert(io.open(T.root..'chunk_scaling/'..name,'wb'));f:write(T.J.encode(value));f:close()
end
return T
