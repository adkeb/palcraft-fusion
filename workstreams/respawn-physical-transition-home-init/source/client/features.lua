-- Inert factory for the input owner's single game-thread callback. No timer or socket.
local dir=assert(debug.getinfo(1,'S').source:match('^@(.*[/\\])'))
local M={version=1}
local function uid(pc)
 local g=pc:GetPlayerUId()
 return('%08x-%04x-%04x-%04x-%04x%08x'):format(g.A&0xffffffff,(g.B>>16)&0xffff,g.B&0xffff,(g.C>>16)&0xffff,g.C&0xffff,g.D&0xffffffff)
end
function M.new(o)
 o=o or{};local rt=o.runtime_dir or(dir..'runtime/')
 local Compose=dofile(rt..'compose.lua');local IO=dofile(rt..'io.lua');local Session=dofile(rt..'session.lua')
 local J=assert(o.json);local root=IO.root(assert(o.bridge_root));local F=IO.new(J,o.files)
 local now=o.now or os.time;local load=o.load or function(name)return dofile(dir..name..'.lua')end
 local api={running=true,binding=nil,next_session=0};local C=Compose.new{game_thread=o.game_thread,on_error=o.on_error};api.composition=C
 local bootstrap
 if o.native_mc_bootstrap_enabled==true then
  bootstrap=dofile(rt..'bootstrap.lua').new{session=Session,read=F.read,now=now,path=root..'mc-bootstrap-status.json'}
  o.native_binding=o.native_binding or function(host)return bootstrap.binding(host)end
 end
 local renderer=o.entity_renderer
 if not renderer and o.entity_visuals_enabled==true then
  renderer=load('entity_renderer_proxy').new(function()
   local companion=api.last_companion
   return companion and companion.visual_pipeline and companion.visual_pipeline.capture_renderer
  end)
 end
 C:register('host',{interval_ms=250,ready=function()return api.binding~=nil,api.binding_error or'authenticated_host_unavailable'end,
  factory=function()return api.binding end,status=function(worker)return{protocol=2,pal_uid=worker.pal_uid,mc_uuid=worker.mc_uuid,
   session_id=worker.session_id,generation=worker.generation,server_session_id=worker.server_session_id,mc_epoch_verified=false}end})
 C:register('native_mc',{enabled=o.native_mc_bootstrap_enabled==true,disabled_reason='native_MC_bootstrap_not_selected',
  depends={'host'},interval_ms=250,ready=function()
   local b,why=bootstrap.binding(api.binding);api.mc_binding=b
   api.mc_view=b and bootstrap.current.world_view or nil
   return b~=nil,why
  end,key=function()
   local b,v=api.mc_binding,api.mc_view
   return b.mc_epoch..'/'..b.session_id..'/'..b.generation..'/'..v.world_session
  end,factory=function()return{}end,status=function()return bootstrap.status()end,
  stop=function(_,reason,ctx)
   api.initialized_native_world=nil
   if o.view_bridge then assert(o.view_bridge.reset(reason,not ctx or ctx.context_alive~=false)==true,'Native WorldView reset failed')end
  end})
 C:register('commands',{enabled=o.command_bus~=nil,disabled_reason='native_command_sender_not_selected',
  depends={'host'},interval_ms=0,factory=function()return o.command_bus end,
  tick=function(bus)bus.tick()end,status=function(bus)return bus.status()end,stop=function(bus)bus.reset()end})
 local client_world
 if o.client_world then C:register('client_world',{depends={'host','native_mc'},interval_ms=50,
  key=function()return o.client_world.key(api)end,
  factory=function(ctx)client_world=o.client_world.new(ctx,api);return client_world end,
  tick=function(worker,ms,ctx)worker:tick(ms,ctx)end,status=function(worker)return worker:status()end,
  is_ready=function(s)return s.ready==true end,
  stop=function(worker,reason,ctx)assert(worker:stop(reason,ctx)==true,'Client world cleanup failed');client_world=nil end})end
 C:register('world',{depends=o.client_world and{'host','client_world'}or{'host'},interval_ms=250,ready=function(ctx)
  if not(ctx and ctx.collisions and ctx.collisions.running==true)then return false,'collision_companion_not_running'end
  if o.client_world then return client_world:ready()end
  return true
 end,factory=function(ctx)
  local companion=ctx.collisions
  if companion.set_world_observer then
   companion.set_world_observer{on_row=function(row,accepted,reason)return api:on_world(row,accepted,reason)end}
  end
  return companion
 end,tick=function(companion)
  assert(companion.running==true and not companion.error and not companion.observer_error,'Native world companion failed')
 end,status=function(companion)return J.decode(assert(companion.status_json,'Companion-owned status encoder missing')())end,stop=function(companion)
  if companion.set_world_observer then companion.set_world_observer(nil)end
 end})
 C:register('entity_capture',{enabled=o.entity_visuals_enabled==true and o.entity_renderer==nil,
  disabled_reason='captured_entity_visuals_not_selected',depends={'host','native_mc','world'},interval_ms=250,
  ready=function(ctx)
   local pipeline=ctx and ctx.collisions and ctx.collisions.visual_pipeline
   return pipeline and pipeline.attach_capture and pipeline.detach_capture and o.capture~=nil,'capture_pipeline_or_scope_missing'
  end,factory=function(ctx)
   local pipeline=ctx.collisions.visual_pipeline;local options={};for k,v in pairs(o.capture)do options[k]=v end
   options.verify_actor=function(row,actor)
    local observer=api.entity_observer
    return observer and observer.verify_actor(row,actor)==true or false
   end
   return{pipeline=pipeline,worker=assert(pipeline.attach_capture(options),'Capture factory returned nil')}
  end,
  -- Capture binding is ticked by the companion's existing pipeline callback.
  status=function(instance)return instance.worker.status()end,
  stop=function(instance,_,ctx)
   assert(instance.pipeline.detach_capture(not ctx or ctx.context_alive~=false)==true,'Capture lifecycle cleanup failed')
  end})
 C:register('entities',{enabled=o.entities_enabled~=false,depends={'host'},interval_ms=o.entity_interval_ms or 250,
  factory=function()
   local worker=load('entities').new{json=J,root=root..'entities/',session=api.binding.server_session_id,now=now,
    local_realm=o.local_realm,world_id=api.binding.world_id,player_uid=api.binding.pal_uid,
    read=function(name)
     local meta=F.read(root..'entities/binding-meta.json');local b=api.binding
     if not meta or not b or meta.schema~=1 or meta.state~='bound'or meta.stale~=false
      or meta.host_session_id~=b.session_id or meta.generation~=b.generation or meta.server_session_id~=b.server_session_id
      or not meta.identity or meta.identity.pal_uid~=b.pal_uid or meta.identity.mc_uuid~=b.mc_uuid or meta.identity.world_id~=b.world_id
      or type(meta.updated_unix)~='number'or now()-meta.updated_unix>3 or now()-meta.updated_unix< -5 then return nil end
     return F.read(root..'entities/'..name)
    end,renderer=renderer}
   _G.PalCraftEntityObserver=worker
   api.entity_observer=worker
   api.vitals=function(pc)return worker.vitals(pc)end;_G.PalCraftAcceptanceVitals=api.vitals
   return worker
  end,tick=function(worker,ms,ctx)worker.tick(ctx.pc)end,status=function(worker)return worker.status()end,
  is_ready=function(s,worker,ctx)return s.phase=='observing_native_bodies'and worker.vitals(ctx.pc).ok==true end,
  stop=function(worker,_,ctx)worker.stop(not ctx or ctx.context_alive~=false);if api.entity_observer==worker then api.entity_observer=nil end
   if _G.PalCraftEntityObserver==worker then _G.PalCraftEntityObserver=nil end
   if _G.PalCraftAcceptanceVitals==api.vitals then _G.PalCraftAcceptanceVitals=nil end;api.vitals=nil
  end})
 C:register('travel',{enabled=o.travel_enabled==true,disabled_reason='travel_native_readiness_and_transport_not_ready',
  depends={'host','world'},interval_ms=50,ready=function()
   local view=o.view_bridge
   return o.travel~=nil and(o.travel.identity~=nil or o.native_binding~=nil)and o.travel_transport~=nil and o.origin~=nil
    and(view~=nil or(o.travel.commit_frame~=nil and o.travel.host_scope~=nil)),'travel_native_view_or_transport_missing'
  end,factory=function(ctx)
   local options={};for k,v in pairs(o.travel)do options[k]=v end
   options.send=o.travel_transport.send;options.game_thread=o.game_thread
   options.identity=options.identity or function()return o.native_binding(api.binding)end
   options.host_scope=options.host_scope or function()return api.binding end
   local view=o.view_bridge
   if view then
    options.on_hold=options.on_hold or view.hold
    options.set_mapping=options.set_mapping or view.applyMapping
    options.sync_view=options.sync_view or view.syncView
    options.commit_frame=options.commit_frame or view.commitFrame
    options.on_complete=options.on_complete or view.release
    options.on_reset=options.on_reset or view.reset
    options.on_error=options.on_error or function()return view.reset('prepare_aborted',true)end
   end
   return load('travel').new(options)
  end,tick=function(worker,ms,ctx)
   o.travel_transport.poll(function(row)return worker:observe(row)end,api.binding)
   worker:tick(ctx.pc,o.origin,ms,ctx.input)
  end,status=function(worker)return worker:status()end,
  stop=function(worker,reason,ctx)worker:reset(reason,ctx and ctx.context_alive~=false)end})
 C:register('fluid_physics',{enabled=o.fluid_enabled==true,disabled_reason='native_fluid_body_and_movement_not_ready',
  depends={'host','world'},interval_ms=100,ready=function()return o.fluid~=nil,'native_fluid_adapter_missing'end,
  factory=function(ctx)
   local options={};for k,v in pairs(o.fluid)do options[k]=v end
   options.world=ctx.collisions.world;options.origin=o.origin;options.side='client';options.json=J;options.game_thread=o.game_thread
   return load('fluid_physics').new(options)
  end,tick=function(worker,ms,ctx)worker:tick(ms,ctx)end,status=function(worker)return worker:status()end,
  stop=function(worker,reason,ctx)worker:stop(reason,ctx)end,
  events={world=function(worker,row)return worker:on_world(row)end}})
 C:register('sign_text',{enabled=o.sign_enabled==true,disabled_reason='sign_renderer_material_and_image_transport_not_ready',
  depends={'host','world'},interval_ms=250,ready=function(ctx)
   local pipeline=ctx and ctx.collisions and ctx.collisions.visual_pipeline
   if not pipeline or not pipeline.attach_signs or not pipeline.detach_signs then return false,'sign_pipeline_lifecycle_not_ready'end
   if not o.sign or not o.sign.confirmed_view or not o.sign.send_binding or not o.sign.images_ready then return false,'sign_scope_or_image_transport_missing'end
   return o.sign.images_ready(api.binding)
  end,factory=function(ctx)
   local options={};for k,v in pairs(o.sign)do options[k]=v end
   local pipeline=ctx.collisions.visual_pipeline
   return{pipeline=pipeline,worker=assert(pipeline.attach_signs(options),'Sign consumer factory returned nil')}
  end,
  -- The companion's one existing tick drives this consumer at250ms; no second timer.
  status=function(instance)return instance.worker:status()end,
  stop=function(instance,reason,ctx)assert(instance.pipeline.detach_signs(not ctx or ctx.context_alive~=false)==true,'Sign lifecycle cleanup failed')end})
 function api:tick(ms,ctx)
  assert(ctx and ctx.pc and ctx.identity,'Client player/session context required')
  if not self.running then return false end
  if self.previous_time and ms<self.previous_time then self.next_session=0 end;self.previous_time=ms
  if ms>=self.next_session then
   self.next_session=ms+250
   local good,value=pcall(function()
    local expected={};for k,v in pairs(assert(o.identity,'Personal MC/Pal identity not configured'))do expected[k]=v end
    expected.server_session_id=ctx.identity.server_session_id
    assert(ctx.pc:IsValid()and ctx.pc.Pawn and ctx.pc.Pawn:IsValid(),'Possessed local player unavailable')
    assert((o.player_uid or uid)(ctx.pc)==expected.pal_uid,'Possessed Pal player differs from configured identity')
    local local_player=ctx.pc.Player
    assert(local_player and local_player:IsValid()and local_player:GetFullName():find('PalLocalPlayer',1,true),'Personal local controller required')
    return Session.host(F.read(root..'session-bind-status.json'),expected,now())
   end)
   if not good then self.binding_error=tostring(value);value=nil else self.binding_error=nil end
   if not Session.same(value,self.binding)then C:reset(value and'host_generation_changed'or'host_unbound',ctx);self.binding=value end
  end
  if self.last_companion and self.last_companion~=ctx.collisions then C:reset('world_companion_changed',ctx)end
  self.last_companion=ctx.collisions
  return C:tick(ms,ctx)
 end
 function api:on_world(row,accepted,reason)
  if accepted~=true then self.world_error=reason;return false end
  self.last_world={session=row.session,seq=row.seq,dim=row.dim};return C:emit('world',row)
 end
 function api:reset(reason,ctx)
  local good=C:reset(reason,ctx);self.binding=nil;self.next_session=0;self.last_companion=nil
  self.mc_binding=nil;self.mc_view=nil;self.initialized_native_world=nil;return good
 end
 function api:bootstrap_view()
  if not bootstrap then return nil,'native_MC_bootstrap_not_selected'end
  return bootstrap.view(self.binding)
 end
 function api:initialize_home(pc)
  local v,why=self:bootstrap_view();if not v then return false,why end
  assert(self.binding and(o.player_uid or uid)(pc)==self.binding.pal_uid,'Local Pal identity changed before WorldView init')
  if v.dim~='minecraft:overworld'then return false,'initial_home_view_pending_authority'end
  if self.initialized_native_world==v.world_session then return true end
  local native=assert(bootstrap.current.native_binding)
  local state=o.view_bridge and o.view_bridge.status and o.view_bridge.status()
  if state then
   local mapping,previous=state.mapping,state.native_context
   local same_native=previous and previous.mc_epoch==native.mc_epoch
    and previous.session_id==native.session_id and previous.generation==native.generation
   if state.held or(same_native and mapping and mapping.world_session==v.world_session
    and mapping.dim==v.dim and mapping.view~=v.view)then
    -- The original travel callback must commit this tuple and release its ACK hold.
    -- Home initialization cannot substitute for that physical mapping transition.
    return false,'physical_mapping_transition_pending'
   end
  end
  assert(o.view_bridge and o.view_bridge.initWorldView(v.world_session,v.dim,v.view,native)==true,'Initial native WorldView commit failed')
  self.initialized_native_world=v.world_session;return true
 end
 function api:status()
  local s=C:status();s.side='client';s.running=self.running;s.binding_error=self.binding_error;s.world_error=self.world_error;s.last_world=self.last_world
  if self.world_error then s.ready=false end
  s.feature_flags={strict_sessions=true,entities_enabled=o.entities_enabled~=false,travel_enabled=o.travel_enabled==true,
   chunk_enabled=o.chunk_enabled==true,exchange_enabled=false,fluid_physics_enabled=o.fluid_enabled==true,entity_visuals_enabled=o.entity_visuals_enabled==true,
   sign_text_enabled=o.sign_enabled==true,native_mc_bootstrap_enabled=o.native_mc_bootstrap_enabled==true}
  return s
 end
 function api:stop(reason,ctx)local good=C:stop(reason,ctx);self.running=false;self.binding=nil;return good,self:status()end
 function api:start(reason,ctx)
  if self.running then return true,self:status()end
  local good=self:reset(reason or'operator_start',ctx)
  if good then C.stopped=false;self.running=true end
  return good,self:status()
 end
 return api
end
return M
