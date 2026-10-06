-- Concrete options driven by features' existing game-thread lifecycle.
-- The companion retains its only world journal/reducer/timer. QA is not forged.
local dir=assert(debug.getinfo(1,'S').source:match('^@(.*[/\\])'))
local M={version=3}
local function copy(t)local r={};for k,v in pairs(t or{})do r[k]=v end;return r end
local function root(p)return assert(p):gsub('\\','/'):gsub('/?$','/')end
local function same_origin(a,b)
 if not a or not b then return false end
 for _,k in ipairs({'X','Y','Z'})do
  if type(a[k])~='number'or type(b[k])~='number'or math.abs(a[k]-b[k])>.001 then return false end
 end
 return(a.y_origin or 64)==(b.y_origin or 64)
end
local function uid(pc)
 local g=pc:GetPlayerUId()
 return('%08x-%04x-%04x-%04x-%04x%08x'):format(g.A&0xffffffff,(g.B>>16)&0xffff,g.B&0xffff,(g.C>>16)&0xffff,g.C&0xffff,g.D&0xffffffff)
end
local function valid_bounds(b)
 if type(b)~='table'or #b~=6 then return false end
 for _,n in ipairs(b)do if not math.tointeger(n)then return false end end
 return b[1]<b[4]and b[2]<b[5]and b[3]<b[6]
end
local function current_receipt(c,v,pc,home)
 -- One actual complete receipt around the possessed player; disjoint
 -- snapshot bounds are never merged into fabricated rectangle coverage.
 local p=pc.Pawn:K2_GetActorLocation()
 local half=assert(pc.Pawn.CapsuleComponent):GetScaledCapsuleHalfHeight()
 assert(type(half)=='number'and half>0 and half<500,'Actual initial player capsule required')
 local at={(p.X-home.X)/100,64+(p.Z-half-home.Z)/100,-(p.Y-home.Y)/100}
 local best
 for _,r in pairs(c.world.committed_snapshots or{})do local b=r.bounds
  if r.committed==true and r.session==v.world_session and r.dim==v.dim
   and(not r.player or r.player==v.player)and type(r.end_seq)=='number'
   and r.end_seq>=(c.world.last_gap_seq or 0)and valid_bounds(b)
   and at[1]>=b[1]and at[1]<b[4]and at[2]>=b[2]and at[2]<b[5]and at[3]>=b[3]and at[3]<b[6]
   and(not best or r.end_seq>best.end_seq)then best=r end
 end
 return best,at
end
function M.new(o)
 o=assert(o);local J,cfg=assert(o.json),assert(o.config)
 local bridge_root,scripts=root(o.bridge_root),root(o.scripts_dir)
 local IO=dofile(dir..'io.lua');local F=IO.new(J,o.files)
 local Session=dofile(dir..'session.lua');local Records=dofile(dir..'records.lua')
 local home=copy(assert(o.origin));local view_bridge=assert(o.view_bridge)
 local commands=Records.commands{json=J,path=bridge_root..'command.json'}
 local now=o.now or os.time;local current;local early_rows={};local startup_input,TravelP
 local options={json=J,bridge_root=bridge_root,origin=o.origin,identity=assert(cfg.identity),files=o.files,now=now,
  runtime_dir=o.runtime_dir or dir,game_thread=o.game_thread,player_uid=o.player_uid,on_error=o.on_error,
  native_mc_bootstrap_enabled=true,entities_enabled=cfg.entities_enabled~=false,
  entity_visuals_enabled=cfg.entity_visuals_enabled==true,sign_enabled=cfg.sign_text_enabled==true,
  fluid_enabled=cfg.fluid_physics_enabled==true,travel_enabled=cfg.travel_enabled==true,
  chunk_enabled=cfg.chunk_enabled==true or cfg.travel_enabled==true,view_bridge=view_bridge,command_bus=commands}
 local material_config=F.read(bridge_root..'material-runtime-v1.json')
 local material_options=o.material_options
 if material_config and material_config.enabled==true then
  assert(material_config.version==1,'Material runtime config version required')
  material_options=copy(material_config);material_options.json=J;material_options.bridge_root=bridge_root
 end
 if material_options then
  material_options=copy(material_options);material_options.json=J;material_options.bridge_root=bridge_root
  material_options.send_query=commands.send
 end
 local function thread()
  local f=o.game_thread or IsInGameThread;assert(type(f)=='function'and f()==true,'client_factory_requires_game_thread')
 end
 local function require_worker()
  assert(current and not current.stopped,'Client world factory not running');return current
 end
 local travel_dir=root(o.travel_dir or(scripts..'travel/'))
 if options.travel_enabled then
  -- The authenticated proxy mirrors BridgeTravelGate's unchanged travel rows
  -- locally. A client on another machine never reads the server's D: journal.
  local events=o.travel_events_path or cfg.travel_events_path or(bridge_root..'travel-events.ndjson')
  local input=Records.tail{json=J,path=events};startup_input=input;TravelP=dofile(travel_dir..'protocol.lua')
  options.travel_transport={send=function(row)
   local types={client_ready='travel_ready',client_observed='travel_observed',client_abort='travel_abort'}
   local query=copy(row);query.t=assert(types[row.phase],'Unknown native travel signal');return commands.send(query)
  end,poll=function(consume)
   local function deliver(row)
    if row.phase=='prepare'and current and not current.stopped then
     local v=current.features:bootstrap_view()
     local b=options.native_binding and options.native_binding(current.features.binding)or current.features.mc_binding
     current:request_target_snapshot(row,b,v)
    end
    return consume(row)
   end
   local queued=early_rows;early_rows={}
   for _,row in ipairs(queued)do deliver(row)end
   return #queued+input.poll(deliver,64)
  end}
  local facade={}
  for _,name in ipairs({'prepare_view','readiness','release','abandon','can_recycle','retirement_status'})do
   facade[name]=function(...)return assert(require_worker().chunks,'Native chunk views not installed').view[name](...)end
  end
  function facade.activate(ticket)
   local w=require_worker();assert(w.chunks.view.activate(ticket)==true,'Native chunk activation failed')
   -- Change the reducer's dimension/player only after the native target commits.
   w.companion.set_view(ticket.dim,ticket.player);return true
  end
  options.travel={view=facade,module_dir=travel_dir,readers=o.readers,
   verify_identity=function(pc,b,authority)
    local w=require_worker();local h=w.features.binding;local n=w.features.mc_binding
    if authority or not h or not n or not Session.same(n,b)or uid(pc)~=b.pal_uid then return false,'client_travel_identity_changed'end
    if o.local_realm then local proof=o.local_realm:current();if not proof or o.local_realm:validate(proof,pc)~=true or proof.server_session_id~=b.server_session_id then return false,'standalone_travel_context_changed'end end
    local player=pc.Player
    if not player or not player:IsValid()or not player:GetFullName():find('PalLocalPlayer',1,true)then return false,'personal_local_controller_required'end
    return h.pal_uid==b.pal_uid and h.mc_uuid==b.mc_uuid and h.world_id==b.world_id
     and h.server_session_id==b.server_session_id,'client_host_scope_changed'
   end,
   on_complete=function(status)
    assert(view_bridge.release(status)==true,'Native camera final ACK release failed')
    local w=require_worker();local t=w.chunks.initial_ticket
    if t and not t.released and w.chunks.views.active_view~=t then assert(w.chunks.view.release(t)==true,'Initial scene retirement failed')end
    return true
   end}
 end
 if options.fluid_enabled then
  options.fluid={root=bridge_root,json=J,shared_dir=root(o.fluid_shared_dir or(scripts..'fluid/')),
   dll_path=o.fluid_dll or(scripts..'../../../../PalCraftFluidPhysics-v1.dll'),log_path=o.log_path or(scripts..'../../../UE4SS.log')}
  for k,v in pairs(o.fluid_options or{})do options.fluid[k]=v end
  options.fluid.resolve_participants=options.fluid.resolve_participants or function(ctx)
   -- Prediction cannot push a pawn while travel waits for target replication.
   local scope=view_bridge.status();local mapping=scope.mapping
   if scope.held or not mapping or not mapping.world_session or not mapping.view then return{}end
   local w=require_worker();local pc=assert(ctx.pc);local h=w.features.binding
   assert(h and pc:IsValid()and pc.Pawn and pc.Pawn:IsValid()and uid(pc)==h.pal_uid,'Authenticated local fluid pawn required')
   return{{id='player:'..h.pal_uid,actor=pc.Pawn,dim=w.companion.world.dimension,
    player=true,player_filter=w.companion.world.player}}
  end
 end
 local function scene()
  local w=current;if not w or w.stopped or not w.started then return end
  local c=w.companion;local v=w.features:bootstrap_view()
  if not v or v.waiting_ack or c.running~=true or c.error or c.world_error or c.observer_error
   or c.world.needs_resync or c.world.session~=v.world_session or c.world.dimension~=v.dim
   or c.pending_view or c.world.pending_view then return end
  local s=view_bridge.status();local m=s.mapping
  if s.held or not m or m.world_session~=v.world_session or m.dim~=v.dim or m.view~=v.view then return end
  local origin,bounds,mapping
  if w.chunks then
   local t=w.chunks.views.active_view
   if not t or t.released or t.world_session~=v.world_session or t.dim~=v.dim or t.view~=v.view then return end
   local proof=w.chunks.view.readiness(t);if proof.ready~=true then return end
   origin,bounds,mapping=t.mapping.origin,t.required_bounds,t.region_id
   if not same_origin(origin,o.origin)then return end
  else
   if v.dim~='minecraft:overworld'or not same_origin(c.origin,home)or not same_origin(o.origin,home)
    or #c.queue-(c.queue_head or 1)+1>0 then return end
   local receipt=current_receipt(c,v,w.ctx.pc,home);if not receipt then return end
   origin,bounds=c.origin,receipt.bounds
   mapping='per-block-origin:'..J.encode({origin.X,origin.Y,origin.Z,origin.y_origin or 64})
  end
  return{fence={world_session=v.world_session,dim=v.dim,view=v.view,mapping=mapping,mc_uuid=v.player},
   origin=origin,bounds={table.unpack(bounds)}}
 end
 if options.entity_visuals_enabled then
  local function current_host()
   local w=current;local h=w and not w.stopped and w.features.binding
   if not h then return end
   local q=F.read(bridge_root..'session-bind-status.json');local ok,b=pcall(Session.host,q,h,now())
   if not ok or not Session.same(b,h)then return end
   return h
  end
  options.capture={send_binding=commands.send,now_ms=o.now_ms or function()return now()*1000 end,
   current_view=function()
    if not current_host()then return end
    -- scene() retains the accepted camera/ACK gate and actual committed bounds.
    return scene()
   end,
   verify_host_session=function(envelope,row)
    local h=current_host();if not h or type(envelope)~='table'or envelope.v~=2 or envelope.legacy~=false then return false end
    for _,key in ipairs({'world_id','pal_uid','mc_uuid','mc_name','server_session_id','session_id','generation'})do
     if envelope[key]~=h[key]then return false end
    end
    return row.mc_uuid==h.mc_uuid and type(envelope.expires_at)=='number'and envelope.expires_at>now()
   end}
 end
 if options.sign_enabled then
  options.sign={allow_candidate=cfg.lab_candidate~=false,profiles=cfg.sign_profiles,verified_profiles=cfg.verified_sign_profiles,
   send_binding=commands.send,images_ready=function(host)
    -- The proxy publishes this only after constructing the real receiver.
    -- It needs neither a first bind request nor an as-yet unrequested PNG.
    local q=F.read(bridge_root..'session-bind-status.json')
    local ok,b=pcall(Session.host,q,host,now())
    if not ok or not Session.same(b,host)then return false,'sign_receiver_host_receipt_stale'end
    local r=q.sign_text_receiver
    return type(r)=='table'and r.version==1 and r.installed==true,'sign_text_image_receiver_not_installed'
   end,
   view_provider=function()return scene()end,
   confirmed_view=function()
    local v=scene();if not v then return end
    return{applied=true,world_session=v.fence.world_session,dim=v.fence.dim,view=v.fence.view,
     mapping=v.fence.mapping,mc_uuid=v.fence.mc_uuid}
   end,
   block_at=function(dim,at)
    local w=current;if not w or w.stopped then return nil,false end
    local c=w.companion;local g=c.world:get(dim,table.unpack(at));if not g then return nil,false end
    local e
    if c.block_render_entry then e=c.block_render_entry(dim,at)
    elseif not w.chunks then e=c.actors[('%d:%d:%d'):format(table.unpack(at))]end
    local committed=c.world.dimension==dim and e and(not e.dim or e.dim==dim)and e.model~=nil
     and e.model_status=='rendered'and e.id==g.id and e.visible~=false and e.render_signature==c.render_signature(g)
    if committed and o.model_live then committed=o.model_live(e.model,e.model_component)==true end
    return g,committed==true
   end}
 end
 if options.chunk_enabled or options.fluid_enabled or options.sign_enabled or options.entity_visuals_enabled or material_options then
  local Worker={};Worker.__index=Worker
  options.client_world={key=function(features)
   local b,v=assert(features.mc_binding),assert(features.mc_view)
   return b.mc_epoch..'/'..b.session_id..'/'..b.generation..'/'..v.world_session
  end,new=function(ctx,features)
   thread();assert(not current or current.stopped,'Client world factory already running')
   current=setmetatable({features=features,companion=assert(ctx.collisions),ctx=ctx,
    started=false,reason='initial_native_scene_pending'},Worker);return current
  end}
  local function native_match(row,b,v)
   return TravelP.envelope(row)and TravelP.binding(b)and row.player==b.mc_uuid and row.pal_uid==b.pal_uid
    and row.session_id==b.session_id and row.session_generation==b.generation and row.mc_epoch==b.mc_epoch
    and row.world_id==b.world_id and row.server_session_id==b.server_session_id
    and row.world_session==v.world_session and row.dim==v.dim and row.view==v.view
  end
  function Worker:request_target_snapshot(row,b,v)
   if not v or row.phase~='prepare'or not native_match(row,b,v)or not TravelP.mapping(row.mapping)
    or row.mapping.world_session~=v.world_session or row.mapping.dim~=v.dim
    or row.mapping.scale~=100 or row.mapping.y_origin~=64 or not valid_bounds(row.required_bounds)
    or not TravelP.vector(row.pos)or not TravelP.ue(row.target_pawn)
    or not TravelP.contains(row.mapping.region_bounds,row.target_pawn)then return false end
     -- Hello/auto sync covers 32 blocks. Request the real target ring once per
     -- authenticated tuple before scene readiness starts the travel feature.
     -- Issuing this request never asserts snapshot coverage or native readiness.
     local key=b.mc_epoch..'/'..b.session_id..'/'..b.generation..'/'..v.world_session..'/'..v.dim..'/'..v.view
     if self.snapshot_requested_tuple~=key then
      local bounds=row.required_bounds;local x,z=math.floor(row.pos[1]),math.floor(row.pos[3])
      local radius=math.max(x-bounds[1],bounds[4]-1-x,z-bounds[3],bounds[6]-1-z,1)
      assert(radius<=64,'Authoritative target ring exceeds public blocksync capacity')
      assert(commands.send{t='blocksync',r=radius,world_session=v.world_session,dim=v.dim,view=v.view}==true,
       'Initial authoritative snapshot request failed')
      self.snapshot_requested_tuple=key;self.snapshot_requested_radius=radius
     end
   return true
  end
  function Worker:startup_prepare(v)
   local b=options.native_binding and options.native_binding(self.features.binding)or self.features.mc_binding
   if not startup_input or not TravelP.binding(b)then return end
   -- Pump the SAME bounded travel tail while the world feature is waiting.
   -- This is control data already accepted by HostSession, not a world reader.
   startup_input.poll(function(row)
    if native_match(row,b,v)then
     assert(#early_rows<256,'Cold travel startup queue full');early_rows[#early_rows+1]=TravelP.copy(row)
    else self.startup_rejected=(self.startup_rejected or 0)+1 end
   end,64)
   for _,row in ipairs(early_rows)do
    if row.phase=='prepare'and native_match(row,b,v)and TravelP.mapping(row.mapping)
     and row.mapping.world_session==v.world_session and row.mapping.dim==v.dim
     and row.mapping.scale==100 and row.mapping.y_origin==64 and valid_bounds(row.required_bounds)
     and TravelP.vector(row.pos)and TravelP.ue(row.target_pawn)
     and TravelP.contains(row.mapping.region_bounds,row.target_pawn)then
     self:request_target_snapshot(row,b,v)
     return row,b
    end
   end
  end
  function Worker:tick(_,ctx)
   thread();self.ctx=ctx;local c=self.companion
   assert(ctx.collisions==c,'Client companion changed without lifecycle reset')
   assert(c.running==true and not c.error and not c.world_error and not c.observer_error,'Client companion failed')
   local v,why=self.features:bootstrap_view()
   if not v then self.reason=why;return end
   if material_options then
    local pipeline=c.visual_pipeline
    if not pipeline or not pipeline.add_material_handler or not pipeline.remove_material_handler then
     self.reason='material_pipeline_entry_pending';return
    end
    if not self.material_wiring then
     self.material_wiring=dofile(scripts..'material_live_wiring.lua').attach{models=assert(c.models),pipeline=pipeline,
      companion=c,material_options=material_options}
    end
    -- This is the actual current MC tuple, including hidden prepare while it
    -- waits for ACK. The existing WorldView transaction owns visible commit.
    pipeline.bind_material_scope{mc_uuid=v.player,world_session=v.world_session,dim=v.dim,view=v.view}
   end
   local prepared,binding
   if not self.started and options.travel_enabled then prepared,binding=self:startup_prepare(v)end
   if c.world.session~=v.world_session then self.reason='native_scene_world_session_pending';return end
   if self.started then self.reason=nil;return end
   if not self.chunks then
    local P=TravelP or dofile(travel_dir..'protocol.lua');local initial,mapping
    local native_home=v.dim=='minecraft:overworld'and same_origin(c.origin,home)and same_origin(o.origin,home)
    if not native_home then
     if not options.travel_enabled or not prepared then self.reason='initial_authoritative_prepare_pending';return end
     -- Cold Nether/End/reconnect: use the actual server prepare's mapping/bounds.
     -- Do not choose an arena from config or stamp an applied camera view here.
     mapping=P.copy(prepared.mapping);self.initial_from_prepare=true
     initial={player=prepared.player,world_session=prepared.world_session,dim=prepared.dim,view=prepared.view,
      session_id=binding.session_id,session_generation=binding.generation,mc_epoch=binding.mc_epoch,
      mapping=mapping,required_bounds=P.copy(prepared.required_bounds),mode='client'}
    else
     if v.waiting_ack and not options.travel_enabled then self.reason='initial_native_overworld_authority_pending';return end
     local receipt,at=current_receipt(c,v,ctx.pc,home)
     if not receipt or c.world.needs_resync then self.reason='initial_committed_snapshot_pending';return end
     if not options.chunk_enabled then
      if #c.queue-(c.queue_head or 1)+1>0 then self.reason='initial_native_scene_queue_pending';return end
      c.set_view(v.dim,v.player);self.started=true;self.reason=nil;return
     end
     local config=P.copy(o.travel_config or dofile(travel_dir..'config.lua'));config.home_origin=P.copy(home)
     mapping=assert(P.registry(config):acquire(v.world_session,v.dim,at,'initial_client_scene'))
     assert(mapping.native_overworld==true and same_origin(mapping.origin,home),'Initial scene cannot use auxiliary Overworld')
     local b=assert(self.features.mc_binding)
     initial={player=v.player,world_session=v.world_session,dim=v.dim,view=v.view,
      session_id=b.session_id,session_generation=b.generation,mc_epoch=b.mc_epoch,mapping=mapping,
      required_bounds={table.unpack(receipt.bounds)},mode='client'}
    end
    local models=assert(c.models,'server/main.lua must expose actual companion Models')
    local info=assert(models.status(),'Actual Models status required')
    local chunk=copy(o.chunk_options)
    chunk.client_dir=scripts;chunk.companion=c;chunk.models=models;chunk.json=J;chunk.root=bridge_root
    chunk.context=assert(c.context,'server/main.lua companion.context required')
    chunk.world_session=v.world_session;chunk.player=v.player;chunk.initial_view=initial
    chunk.asset_root=assert(info.asset_root,'Models asset_root unavailable');chunk.geometry_version=info.geometry_version or models.geometry_version or 2
    -- Use the companion's configured selection/cache and asset package.
    chunk.geometry=chunk.geometry or{geometry=assert(models.geometry)}
    chunk.collision_dll=chunk.collision_dll or o.chunk_collision_dll or(scripts..'../../../../PalCraftChunkCollision-v1.dll')
    chunk.log_path=chunk.log_path or o.log_path or(scripts..'../../../UE4SS.log')
    self.chunks=dofile(dir..'chunks.lua').new(chunk)
    if options.travel then options.travel.initial_mapping=P.copy(mapping)end
   end
   local proof=self.chunks.view.readiness(self.chunks.initial_ticket);self.initial_proof=proof
   if proof.ready~=true then self.reason='initial_native_scene_commit_pending';return end
   if not self.initial_from_prepare then
    assert(self.chunks.view.activate(self.chunks.initial_ticket)==true,'Initial native scene activation failed')
    c.set_view(v.dim,v.player)
   end
   -- Target readiness opens only the travel lifecycle. Actual activation,
   -- origin/camera commit and final ACK remain the existing travel transaction.
   self.started=true;self.reason=nil
  end
  function Worker:ready()
   if self.stopped or not self.started then return false,self.reason or'initial_native_scene_pending'end
   local c=self.companion
   if c.running~=true or c.error or c.world_error or c.observer_error or c.chunk_consumer_error then return false,'client_native_scene_failed'end
   local v,why=self.features:bootstrap_view()
   if not v or c.world.session~=v.world_session then return false,why or'native_scene_world_session_pending'end
   -- Travel retains the source while waiting for replication/camera commit.
   -- Sign rendering waits independently for the accepted active target tuple.
   return true
  end
  function Worker:status()
   local ready,reason=self:ready()
   return{version=M.version,ready=ready,reason=reason,started=self.started,companion_driven=true,
    initial_proof=self.initial_proof,initial_from_prepare=self.initial_from_prepare==true,startup_rejected=self.startup_rejected or 0,
    chunks=self.chunks and self.chunks.status(),material_runtime=self.material_wiring and self.material_wiring.status(),in_game_verified=false,
    snapshot_requested_tuple=self.snapshot_requested_tuple,snapshot_requested_radius=self.snapshot_requested_radius}
  end
  function Worker:stop(_,ctx)
   thread();local c=self.companion;local alive=not ctx or ctx.context_alive~=false
   if self.chunks and c.chunk_consumer==self.chunks.bridge.binding then
    assert(self.chunks.stop(alive)==true,'Client chunk cleanup failed')
    if c.chunk_consumer==self.chunks.bridge.binding then c.chunk_consumer=nil end
   end
   if self.material_wiring then self.material_wiring.stop();self.material_wiring=nil end
   self.stopped=true;self.started=false;early_rows={};if current==self then current=nil end;return true
  end
 end
 return options
end
return M
