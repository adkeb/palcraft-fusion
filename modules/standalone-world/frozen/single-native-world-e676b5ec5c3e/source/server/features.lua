-- Load from the full PalLiveBridge dispatcher, never from the collision companion.
-- Construction is inert. The dispatcher calls tick/dispatch/stop on its game thread.
local dir=assert(debug.getinfo(1,'S').source:match('^@(.*[/\\])'))
local M={version=1}
function M.new(o)
 o=o or{};local rt=o.runtime_dir or(dir..'runtime/')
 local Compose=dofile(rt..'compose.lua');local IO=dofile(rt..'io.lua');local Session=dofile(rt..'session.lua')
 local J=assert(o.json,'Runtime JSON required');local R=assert(o.readers,'Authority readers required')
 local bridge=IO.root(o.bridge_root or'D:/PalworldServer-LAN/PalCraft-Dev/bridge/')
 local auth=IO.root(o.auth_root or'D:/PalworldServer-LAN/BridgeLab/rpc/session-auth/');local entities=IO.root(o.entities_root or(bridge..'entities/'))
 local F=IO.new(J,o.files);local now=o.now or os.time
 local load=o.load or function(name)return dofile(dir..(name=='exchange'and'palcraft-exchange'or name)..'.lua')end
 local api={running=true,bridge_root=bridge,auth_root=auth,registry=nil,presence=nil}
 local C=Compose.new{game_thread=o.game_thread,on_error=o.on_error};api.composition=C
 local function authority()
  return api.presence and api.presence.authority==true,api.presence and api.presence.error or'pal_authority_unavailable'
 end
 C:register('presence',{interval_ms=1000,factory=function()
  local worker=load('session-auth').new{root=auth,json=J,readers=R,local_realm=o.local_realm}
  api.auth=worker;_G.PalCraftSessionAuth=worker;return worker
 end,tick=function(worker)api.presence=worker.tick()or api.presence end,
  status=function()return api.presence end,is_ready=function(s)return s and s.authority==true end,
  stop=function(worker)if _G.PalCraftSessionAuth==worker then _G.PalCraftSessionAuth=nil end;api.auth=nil;api.presence=nil end})
 C:register('sessions',{depends={'presence'},interval_ms=1000,ready=function()
  local good,reason=authority();if good~=true then api.registry=nil;return false,reason end
  local ok,value=pcall(Session.registry,F.read(auth..'authenticated-sessions.json'),api.presence,now())
  if not ok then api.registry=nil;return false,tostring(value)end
  api.registry=value;return true
 end,factory=function()return{}end,status=function()
  local n=0;for _ in pairs(api.registry and api.registry.by_mc or{})do n=n+1 end
  return{protocol=2,mode='strict',authenticated_players=n,world_id=api.registry and api.registry.world_id,
   server_session_id=api.registry and api.registry.server_session_id,mc_epoch=api.registry and api.registry.mc_epoch}
 end,is_ready=function(s)return s.authenticated_players>0 end})
 C:register('world',{depends={'presence'},interval_ms=250,ready=function()
  local c=o.companion and o.companion();return c and c.running==true,'collision_companion_not_running'
 end,key=function()return o.companion()end,factory=function()
  local c=o.companion()
  if c.set_world_observer then c.set_world_observer({on_row=function(row,accepted,reason)return api:on_world(row,accepted,reason)end},o.world_observer_owner)end
  api.companion=c;return c
 end,tick=function(c)assert(c.running and not c.error and not c.observer_error,'Native collision companion failed')end,
  status=function(c)return J.decode(assert(c.status_json,'Companion-owned status encoder missing')())end,
  stop=function(c)if c.set_world_observer then c.set_world_observer(nil,o.world_observer_owner)end;api.companion=nil end})
 -- Publishing Pal authority is useful before the MC guest finishes login. Damage still
 -- requires the worker's fresh authenticated-sessions proof at the mutation boundary.
 C:register('entities',{enabled=o.entities_enabled~=false,depends={'presence'},interval_ms=o.entity_interval_ms or 250,
  ready=authority,key=function()return api.presence.world_id..'/'..api.presence.server_session_id end,factory=function()
   assert(not _G.PalCraftEntityAuthority,'Entity authority already owned by another lifecycle')
   local worker=load('entities').new{root=entities,json=J,readers=R,origin=assert(o.origin),
    session=api.presence.server_session_id,world_id=api.presence.world_id,sessions_file='authenticated-sessions.json',
    food_enabled=o.food_enabled==true,environment_contact=o.environment_contact,
    read=function(name)return F.read(name=='authenticated-sessions.json'and(auth..name)or(entities..name))end,
    write=function(name,value)return F.write(entities..name,value)end,now=now}
   _G.PalCraftEntityAuthority=worker;return worker
  end,tick=function(worker)
   local status=worker.tick();assert(status and status.running~=false,'Entity authority stopped: '..J.encode(status or{}))
  end,status=function(worker)return worker.status()end,is_ready=function(s)return s.running==true and s.phase=='active'end,stop=function(worker)
   worker.stop();if _G.PalCraftEntityAuthority==worker then _G.PalCraftEntityAuthority=nil end
  end})
 C:register('exchange_bootstrap',{enabled=o.bootstrap_enabled==true or o.exchange_enabled==true,
  disabled_reason='normal_start_boot_observer_not_configured',depends={'presence'},interval_ms=500,
  ready=function()
   if o.bootstrap_hold_reason then return false,o.bootstrap_hold_reason end
   return o.bootstrap~=nil,'normal_start_boot_observer_dependencies_missing'
  end,
  factory=function()
   local options={};for k,v in pairs(o.bootstrap)do options[k]=v end;options.json=J;options.readers=R
   local worker=options.early_observer or load('exchange_bootstrap').new(options);api.boot_observer=worker;return worker
  end,tick=function(worker)worker.tick()end,status=function(worker)return worker.status()end,
  is_ready=function(status)return status.ready==true end,
  stop=function(worker)if worker.stop then worker.stop()end;api.boot_observer=nil end})
 C:register('exchange',{enabled=o.exchange_enabled==true,disabled_reason='exchange_escrow_and_save_witness_not_ready',
  depends={'presence'},interval_ms=500,ready=function()
   if o.exchange then return true end -- Constructor restores held guards before admission.
   if not o.exchange_ready then return false,'exchange_escrow_and_save_witness_adapter_missing'end
   return o.exchange_ready()
  end,factory=function()
   if o.exchange then
    local options={};for k,v in pairs(o.exchange)do options[k]=v end;options.json=J;options.readers=R
    return load('exchange').new(options)
   end
   return assert(o.exchange_factory,'Exchange singleton factory required')()
  end,tick=function(worker)
   if o.exchange and(not api.boot_observer or api.boot_observer.ready()~=true)then return end
   worker.tick()
  end,status=function()return{enabled=true,boot_ready=api.boot_observer and api.boot_observer.ready()or false,
   save_witness='external_supervised_dependency',new_transactions='require_actual_boot_and_save_proofs'}end,
  is_ready=function(status)return not o.exchange or status.boot_ready==true end,
  stop=function(worker)if worker.stop then worker.stop()end end,
  routes={palcraft_exchange=function(worker,p,req)
   if o.exchange and(not api.boot_observer or api.boot_observer.ready()~=true)then return{ok=false,status='feature_not_ready',reason='normal_process_boot_not_verified'}end
   p.id=assert(req and req.id);return worker.handle(p)
  end}})
 C:register('fluid_physics',{enabled=o.fluid_enabled==true,disabled_reason='native_fluid_body_and_movement_not_ready',
  depends={'world','entities'},interval_ms=100,ready=function()return o.fluid~=nil,'native_fluid_adapter_missing'end,
  factory=function()
   local options={};for k,v in pairs(o.fluid)do options[k]=v end
   options.world=api.companion.world;options.origin=o.origin;options.side='server';options.json=J;options.game_thread=o.game_thread
   return load('fluid_physics').new(options)
  end,tick=function(worker,ms,ctx)worker:tick(ms,ctx)end,status=function(worker)return worker:status()end,
  stop=function(worker,reason,ctx)worker:stop(reason,ctx)end,
  events={world=function(worker,row)return worker:on_world(row)end}})
 local function resolve(uuid)
  local registry=api.registry;if not registry or now()-registry.updated_unix>5 then return nil end
  local h=registry.by_mc[uuid];if not h then return nil end
  local pc
  if o.resolve_player then pc=o.resolve_player(h.pal_uid)
  else
   for _,candidate in ipairs(FindAllOf('PalPlayerController')or{})do
    if candidate:IsValid()and not candidate:GetFullName():find('Default__',1,true)and candidate:HasAuthority()and candidate.Pawn and candidate.Pawn:IsValid()then
     local g=candidate:GetPlayerUId();local uid=R.guid_to_string({A=g.A,B=g.B,C=g.C,D=g.D}):lower()
     if uid==h.pal_uid then assert(not pc,'Duplicate authoritative player controller');pc=candidate end
    end
   end
  end
  if not pc then return nil end
  local b={};for k,v in pairs(h)do b[k]=v end;b.pc=pc;return b
 end
 api.resolve=resolve
 local function observe(worker,p,req)
  local b=resolve(p.player);if not b then return{ok=false,status='unbound_or_offline_player'}end
  assert(o.verify_travel_request and o.verify_travel_request(p,req,b)==true,'Trusted MC travel request required')
  local ok,reason=worker:observe_client(p,b);return{ok=ok==true,status=ok and'queued'or'rejected',reason=reason}
 end
 C:register('travel',{enabled=o.travel_enabled==true,disabled_reason='travel_native_readiness_and_transport_not_ready',
  depends={'sessions'},interval_ms=50,ready=function()
   if not o.travel or not o.travel.view or not o.travel.send or not o.travel.journal or not o.verify_travel_request then
    return false,'travel_native_view_or_transport_missing'
   end
   return true
  end,factory=function()
   local options={};for k,v in pairs(o.travel)do options[k]=v end
   options.resolve=resolve;options.readers=R;options.game_thread=o.game_thread
   return load('travel').new(options)
  end,tick=function(worker,ms)
   if o.travel_input then
    o.travel_input.poll(function(row)
     local b=resolve(row.player)
     if not b then api.travel_input_error='unbound_or_offline_player';return end
     for _,key in ipairs({'pal_uid','session_id','mc_epoch','world_id','server_session_id'})do
      if row[key]~=b[key]then api.travel_input_error='stale_native_travel_binding:'..key;return end
     end
     if row.session_generation~=b.generation then api.travel_input_error='stale_native_travel_generation';return end
     local accepted,reason=worker:observe_client(row,b)
     if accepted~=true then api.travel_input_error=reason end
    end,64)
   end
   worker:tick(ms)
  end,status=function(worker)return worker:status()end,
  stop=function(worker,reason,ctx)
   assert(worker.stop,'Travel lifecycle stop missing');local good,handoff=worker:stop(reason,not ctx or ctx.context_alive~=false)
   assert(good==true,'Travel lifecycle stop failed');api.retained_travel_handoff=handoff
   -- Retain opaque native tickets in memory, but publish only JSON-safe scene identities.
   local scenes={};for _,scene in ipairs(handoff and handoff.retained_scenes or{})do
    scenes[#scenes+1]={player=scene.player,pal_uid=scene.pal_uid,region_id=scene.mapping and scene.mapping.region_id,
     dim=scene.mapping and scene.mapping.dim,occupied=scene.occupied==true}
   end
   api.retained_travel_scenes={reason=reason,scenes=scenes,count=#scenes,context_alive=not ctx or ctx.context_alive~=false}
  end,
  events={world=function(worker,row)assert(worker:observe_world(row)~=false,'Travel world event rejected')end},
  routes={travel_ready=observe,travel_observed=observe,travel_abort=observe}})
 function api:tick(ms)
  if not self.running then return false end
  return C:tick(ms,self)
 end
 function api:on_world(row,accepted,reason)
  assert(accepted==true,'World consumer rejected row: '..tostring(reason));return C:emit('world',row)
 end
 function api:dispatch(method,p,req)
  p=p or{}
  if method=='palcraft_features_status'then return true,self:status()
  elseif method=='palcraft_features_stop'then local ok,status=self:stop(p.reason);status.stop_ok=ok;return true,status
  elseif method=='palcraft_features_start'then self.running=true;C.stopped=false;C:reset('operator_start',self);return true,self:status()
  elseif method=='palcraft_session_status'then return true,{presence=self.presence,sessions=C.features.sessions.phase,error=C.features.sessions.reason}
  elseif method=='palcraft_resolve_session'then local b=resolve(p.mc_uuid);if b then b.pc=nil end;return true,{ok=b~=nil,binding=b}
  elseif method=='palcraft_travel_retry'then
   local f=C.features.travel
   if f.phase~='running'or not f.instance then return true,{ok=false,reason=f.error or f.reason or f.phase}end
   local b=resolve(p.mc_uuid);assert(b,'Current authenticated player required')
   local worker=f.instance;local tx=assert(worker.pending[b.pal_uid],'Existing travel intent required')
   assert(tx.phase=='error'and tx.error=='target_prepare_timeout','Only an existing prepare timeout may be retried')
   assert(tx.world_session==worker.world_session and tx.world_session==p.world_session,'Current world session required')
   local old=tx.tx;local ok,why=worker:retry(b.mc_uuid)
   return true,{ok=ok==true,reason=why,read_only=false,action='retry_existing_travel',player=b.mc_uuid,
    old_tx=old,new_tx=tx.tx,phase=tx.phase,world_session=tx.world_session,dim=tx.dim,view=tx.view,
    authoritative_ack_issued=false}
  end
  return C:dispatch(method,p,req)
 end
 function api:status()
  local s=C:status();s.side='server';s.running=self.running;s.paths={bridge=bridge,auth=auth,entities=entities}
  s.feature_flags={strict_sessions=true,entities_enabled=o.entities_enabled~=false,travel_enabled=o.travel_enabled==true,
   exchange_enabled=o.exchange_enabled==true,fluid_physics_enabled=o.fluid_enabled==true,food_enabled=o.food_enabled==true,
   boot_observer_enabled=o.bootstrap_enabled==true or o.exchange_enabled==true}
  s.retained_travel_scenes=self.retained_travel_scenes
  s.travel_input_error=self.travel_input_error
  return s
 end
 function api:stop(reason)
  local good=C:stop(reason or'server_stopped',self);self.running=false;return good,self:status()
 end
 return api
end
return M
