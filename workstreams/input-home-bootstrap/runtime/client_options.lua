-- Concrete options driven by features' existing game-thread lifecycle.
-- The companion retains its only world journal/reducer/timer. QA is not forged.
local dir=assert(debug.getinfo(1,'S').source:match('^@(.*[/\\])'))
local M={version=2}
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
 local now=o.now or os.time;local current
 local options={json=J,bridge_root=bridge_root,origin=o.origin,identity=assert(cfg.identity),files=o.files,now=now,
  runtime_dir=o.runtime_dir or dir,game_thread=o.game_thread,player_uid=o.player_uid,on_error=o.on_error,
  native_mc_bootstrap_enabled=true,entities_enabled=cfg.entities_enabled~=false,
  entity_visuals_enabled=cfg.entity_visuals_enabled==true,sign_enabled=cfg.sign_text_enabled==true,
  fluid_enabled=cfg.fluid_physics_enabled==true,travel_enabled=cfg.travel_enabled==true,
  chunk_enabled=cfg.chunk_enabled==true or cfg.travel_enabled==true,view_bridge=view_bridge,command_bus=commands}
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
  local input=Records.tail{json=J,path=events}
  options.travel_transport={send=function(row)
   local types={client_ready='travel_ready',client_observed='travel_observed',client_abort='travel_abort'}
   local query=copy(row);query.t=assert(types[row.phase],'Unknown native travel signal');return commands.send(query)
  end,poll=function(consume)return input.poll(consume,64)end}
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
   if view_bridge.status().held then return{}end
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
 if options.chunk_enabled or options.fluid_enabled or options.sign_enabled then
  local Worker={};Worker.__index=Worker
  options.client_world={key=function(features)
   local b,v=assert(features.mc_binding),assert(features.mc_view)
   return b.mc_epoch..'/'..b.session_id..'/'..b.generation..'/'..v.world_session
  end,new=function(ctx,features)
   thread();assert(not current or current.stopped,'Client world factory already running')
   current=setmetatable({features=features,companion=assert(ctx.collisions),ctx=ctx,
    started=false,reason='initial_native_scene_pending'},Worker);return current
  end}
  function Worker:tick(_,ctx)
   thread();self.ctx=ctx;local c=self.companion
   assert(ctx.collisions==c,'Client companion changed without lifecycle reset')
   assert(c.running==true and not c.error and not c.world_error and not c.observer_error,'Client companion failed')
   local v,why=self.features:bootstrap_view()
   if not v then self.reason=why;return end
   if c.world.session~=v.world_session then self.reason='native_scene_world_session_pending';return end
   if self.started then self.reason=nil;return end
   if not self.chunks then
    -- Initial join with travel enabled deliberately waits for its real camera
    -- ACK. Prepare geometry from the trusted tuple while ACK is pending so the
    -- existing travel transaction can start and publish that target frame.
    if v.dim~='minecraft:overworld'or(v.waiting_ack and not options.travel_enabled)then self.reason='initial_native_overworld_authority_pending';return end
    assert(same_origin(c.origin,home)and same_origin(o.origin,home),'Initial companion must use actual home origin')
    local receipt,at=current_receipt(c,v,ctx.pc,home)
    if not receipt or c.world.needs_resync then self.reason='initial_committed_snapshot_pending';return end
    if not options.chunk_enabled then
     if #c.queue-(c.queue_head or 1)+1>0 then self.reason='initial_native_scene_queue_pending';return end
     c.set_view(v.dim,v.player);self.started=true;self.reason=nil;return
    end
    local P=dofile(travel_dir..'protocol.lua');local config=P.copy(o.travel_config or dofile(travel_dir..'config.lua'))
    config.home_origin=P.copy(home)
    local mapping=assert(P.registry(config):acquire(v.world_session,v.dim,at,'initial_client_scene'))
    assert(mapping.native_overworld==true and same_origin(mapping.origin,home),'Initial scene cannot use auxiliary Overworld')
    local b=assert(self.features.mc_binding);local initial={player=v.player,world_session=v.world_session,dim=v.dim,view=v.view,
     session_id=b.session_id,session_generation=b.generation,mc_epoch=b.mc_epoch,mapping=mapping,
     required_bounds={table.unpack(receipt.bounds)},mode='client'}
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
   assert(self.chunks.view.activate(self.chunks.initial_ticket)==true,'Initial native scene activation failed')
   c.set_view(v.dim,v.player);self.started=true;self.reason=nil
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
    initial_proof=self.initial_proof,chunks=self.chunks and self.chunks.status(),in_game_verified=false}
  end
  function Worker:stop(_,ctx)
   thread();local c=self.companion;local alive=not ctx or ctx.context_alive~=false
   if self.chunks and c.chunk_consumer==self.chunks.bridge.binding then
    assert(self.chunks.stop(alive)==true,'Client chunk cleanup failed')
    if c.chunk_consumer==self.chunks.bridge.binding then c.chunk_consumer=nil end
   end
   self.stopped=true;self.started=false;if current==self then current=nil end;return true
  end
 end
 return options
end
return M
