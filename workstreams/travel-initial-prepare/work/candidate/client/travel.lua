-- Client replica of authoritative travel. Never calls a pawn teleport or SetActorLocation.
-- observe queues data; tick/reset are called by main's existing game-thread loop.
local dir=assert(debug.getinfo(1,'S').source:match('^@(.*[/\\])'))
local M={version=1};local Client={};Client.__index=Client
local function dep(o,name)return o[name]or dofile((o.module_dir or dir..'../travel/')..name..'.lua')end
function M.new(o)
 assert(o and o.identity and o.send and o.view and o.set_mapping and o.sync_view and o.commit_frame and o.host_scope,'travel_client_dependencies_required')
 local P=dep(o,'protocol');local c=o.config or dep(o,'config')
 return setmetatable({options=o,P=P,config=c,actor=o.actor or dep(o,'actor').new{
  protocol=P,config=c,readers=o.readers,game_thread=o.game_thread,verify_identity=o.verify_identity},
  queue={},head=1,retired={},mapping=o.initial_mapping,stats={prepared=0,applied=0,completed=0,rejected=0},faults={}},Client)
end
function Client:_thread()
 local check=self.options.game_thread or IsInGameThread
 assert(type(check)=='function'and check()==true,'travel_requires_game_thread')
end
function Client:observe(row)
 if self.stopped then return false,'travel_client_stopped'end
 if not self.P.envelope(row)then return false,'travel_envelope'end
 if row.phase~='prepare'and row.phase~='committed'and row.phase~='complete'and row.phase~='error'and row.phase~='recovery_required'then return false,'server_phase'end
 if #self.queue-self.head>=1024 then return false,'travel_queue_full'end
 self.queue[#self.queue+1]=self.P.copy(row);return true
end
function Client:_send(phase,extra)
 assert(self.options.send(self.P.message(self.tx,phase,extra))==true,'travel_client_send_failed');self.tx._last_send=self.now
end
function Client:_ticket_release(ticket,context_alive)
 if not ticket then return end
 if context_alive==false then
  assert(self.options.view.abandon and self.options.view.abandon(ticket)==true,'stale_view_abandon_adapter_required')
 else assert(self.options.view.release(ticket)==true,'client_view_release_failed')end
end
function Client:reset(reason,context_alive)
 self:_thread();local tx=self.tx
 if tx then
  if tx._lock then if context_alive~=false then self.actor.release(tx._lock)end;tx._lock=nil end
  if tx._ticket and not tx._applied then self:_ticket_release(tx._ticket,context_alive);tx._ticket=nil end
 end
 self.tx=nil;self.queue={};self.head=1;self.last_reset=reason
 if context_alive==false then
  if self.active_ticket then self:_ticket_release(self.active_ticket,false)end
  self.active_ticket=nil;self.mapping=nil
 end
 if self.options.on_reset then assert(self.options.on_reset(reason,context_alive~=false)==true,'travel_reset_hook_failed')end
 return true
end
function Client:_abort(reason)
 local tx=self.tx;tx.error=reason
 -- A committed server move must remain frozen for forward recovery; dropping the target scene is unsafe.
 if tx._committed or tx._applied then tx.phase='recovery_required';self:_send('client_abort',{error=reason});return end
 tx.phase='error';self:_send('client_abort',{error=reason})
 if tx._lock then self.actor.release(tx._lock);tx._lock=nil end
 if tx._ticket then self:_ticket_release(tx._ticket,true);tx._ticket=nil end
 if self.options.on_error then assert(self.options.on_error(self:status())==true,'travel_error_hook_failed')end
end
function Client:_prepare(row,b,pc)
 local P=self.P;local old=self.tx
 if old and old.tx==row.tx and P.same_binding(old.binding,b)and old._ticket and old.phase~='error'and old.phase~='recovery_required'then
  if old.phase=='prepared'then self:_send('client_ready',{proof=old.proof})end
  if old._applied then self:_send('client_observed',{position=self.actor.position(pc),region_id=old.mapping.region_id,proof=old.proof})end
  return true
 end
 if old and old.world_session==row.world_session and row.view<old.view then return false,'stale_view'end
 if self.retired[row.world_session]then return false,'retired_world_session'end
 if not P.mapping(row.mapping)or row.mapping.dim~=row.dim or row.mapping.world_session~=row.world_session
  or not P.bounds(row.required_bounds)or not P.vector(row.pos)or not P.ue(row.target_pawn)
  or type(row.yaw)~='number'or row.yaw~=row.yaw or type(row.pitch)~='number'or row.pitch~=row.pitch
  or not self.config.dimensions[row.dim]then return false,'travel_prepare_payload'end
 if not P.contains(row.mapping.region_bounds,row.target_pawn)or not P.contains(self.config.world_bounds,row.target_pawn)then return false,'travel_prepare_bounds'end
 local valid,why=self.actor.valid(pc,b,false);if not valid then return false,why end
 if old then
  if old.world_session~=row.world_session then self.retired[old.world_session]=true end
  if old._lock then self.actor.release(old._lock);old._lock=nil end
  if old._ticket and old._ticket~=self.active_ticket then self:_ticket_release(old._ticket,true)end
 end
 if self.options.on_hold then assert(self.options.on_hold(pc)==true,'travel_hold_hook_failed')end
 local tx={tx=row.tx,binding=P.identity(b),world_session=row.world_session,dim=row.dim,view=row.view,
  phase='preparing',mapping=P.copy(row.mapping),required_bounds=P.copy(row.required_bounds),target_pawn=P.copy(row.target_pawn),
  pos=P.copy(row.pos),yaw=row.yaw,pitch=row.pitch,deadline=self.now+self.config.prepare_timeout_ms,
  _pc=pc,_pawn_address=self.actor.snapshot(pc).pawn_address,_source_ticket=self.active_ticket}
 if not self.active_ticket and row.mapping.native_overworld then
  local continuing=old and old.world_session==row.world_session and old.view==row.view and P.same_binding(old.binding,b)
  tx.initial_prepare_started=continuing and old.initial_prepare_started or self.now
  tx.initial_prepare_limit=continuing and old.initial_prepare_limit or self.now+math.max(self.config.prepare_timeout_ms,180000)
 end
 self.tx=tx;tx._lock=self.actor.hold(pc,false)
 tx._ticket=assert(self.options.view.prepare_view(P.request(tx,'client')),'native_client_prepare_missing')
 self.stats.prepared=self.stats.prepared+1;return true
end
function Client:_handle(row,b,pc)
 if row.player~=b.mc_uuid or row.pal_uid~=b.pal_uid or row.session_id~=b.session_id or row.session_generation~=b.generation
  or row.mc_epoch~=b.mc_epoch or row.world_id~=b.world_id or row.server_session_id~=b.server_session_id then return false,'outer_session_mismatch'end
 if row.phase=='prepare'then return self:_prepare(row,b,pc)end
 local tx=self.tx
 if not tx or not self.P.matches(row,tx,b)then return false,'stale_server_message'end
 if row.phase=='committed'then
  if not self.P.ue(row.target_pawn)or self.P.distance(row.target_pawn,tx.target_pawn)>self.config.position_tolerance_cm then return false,'server_commit_position'end
  tx.target_pawn=self.P.copy(row.target_pawn);tx._committed=true;tx.phase=tx._applied and'observed'or'awaiting_replication'
  tx.deadline=self.now+self.config.replication_timeout_ms
 elseif row.phase=='complete'then
  if row.applied~=true or not tx._applied or not self.P.mapping(row.mapping)or row.mapping.region_id~=tx.mapping.region_id then return false,'complete_before_replication'end
  if tx.phase=='complete'then return true end
  tx.phase='complete'
  if tx._lock then self.actor.release(tx._lock);tx._lock=nil end
  if tx._source_ticket and tx._source_ticket~=tx._ticket then self:_ticket_release(tx._source_ticket,true);tx._source_ticket=nil end
  self.active_ticket=tx._ticket;self.stats.completed=self.stats.completed+1
  if self.options.on_complete then assert(self.options.on_complete(self:status())==true,'travel_complete_hook_failed')end
 elseif row.phase=='error'then
  if tx._committed then tx.phase='recovery_required';tx.error=row.error;return true end
  tx.phase='error';tx.error=row.error
  if tx._lock then self.actor.release(tx._lock);tx._lock=nil end
  if tx._ticket then self:_ticket_release(tx._ticket,true);tx._ticket=nil end
  if self.options.on_error then assert(self.options.on_error(self:status())==true,'travel_error_hook_failed')end
 else tx.phase='recovery_required';tx.error=row.error end
 return true
end
function Client:_progress(pc,input)
 local tx=self.tx;if not tx or tx.phase=='complete'or tx.phase=='error'or tx.phase=='recovery_required'then return end
 if self.actor.snapshot(pc).pawn_address~=tx._pawn_address then return self:_abort('client_possession_changed')end
 local req=self.P.request(tx,'client');req.generation=tx._ticket.generation
 local proof=self.options.view.readiness(tx._ticket);local ready,why=self.P.ready(proof,req,'client');tx.waiting=why
 if not tx._committed then self.P.initial_prepare_lease(tx,proof,req,self.now,self.config.prepare_timeout_ms,'client')end
 if self.now>=tx.deadline then return self:_abort(tx._committed and'client_replication_timeout'or'client_prepare_timeout')end
 if ready then tx.proof=self.P.copy(proof)end
 if not ready then
  if tx._committed then return self:_abort(why)end
  return
 end
 if not tx._committed then
  tx.phase='prepared';tx.proof=self.P.copy(proof)
  if not tx._last_send or self.now-tx._last_send>=self.config.resend_ms then self:_send('client_ready',{proof=proof})end
  return
 end
 local at=self.actor.position(pc)
 if self.P.distance(at,tx.target_pawn)>self.config.position_tolerance_cm then return end
 if not tx._applied then
  assert(self.options.view.activate(tx._ticket)==true,'native_client_activation_failed')
  assert(self.options.set_mapping(self.P.copy(tx.mapping),tx.world_session,tx.dim,tx.view)==true,'client_mapping_commit_failed')
  local r=self.P.mc_rotation(tx.yaw,tx.pitch)
  assert(self.options.sync_view(pc,r.Yaw,r.Pitch,input)==true,'client_camera_sync_failed')
  self.mapping=self.P.copy(tx.mapping);self.active_ticket=tx._ticket;tx._applied=true;self.stats.applied=self.stats.applied+1
  if self.options.save then assert(self.options.save({v=1,mapping=self.mapping,world_session=tx.world_session,
   dim=tx.dim,view=tx.view,tx=tx.tx})==true,'client_checkpoint_failed')end
 end
 tx.phase='observed'
 local host=self.options.host_scope()
 if not host then tx.phase='awaiting_camera_commit';tx.waiting='verified_host_scope_missing';return end
 local frame=self.options.commit_frame();local published,detail=self.P.camera_commit(frame,tx,host)
 if not published then tx.phase='awaiting_camera_commit';tx.waiting=detail;return end
 tx._camera_commit=self.P.copy(frame);proof.camera_commit=self.P.copy(frame);tx.proof=self.P.copy(proof)
 if not tx._last_send or self.now-tx._last_send>=self.config.resend_ms or not tx._observed_sent then
  self:_send('client_observed',{position=at,region_id=tx.mapping.region_id,proof=proof});tx._observed_sent=true
 end
end
function Client:tick(pc,origin,now,input)
 self:_thread();self.now=now;self.input=input
 if self.stopped then return self:status()end
 if self.options.receive then for _,row in ipairs(self.options.receive()or{})do self:observe(row)end end
 local b=self.options.identity()
 if not self.P.binding(b)then return{blocked=self.tx~=nil or self.head<=#self.queue,active=false,phase='identity_pending',error='authenticated_binding_required'}end
 if self.tx and not self.P.same_binding(self.tx.binding,b)then
  local queue,head=self.queue,self.head;self:reset('outer_session_changed',true);self.queue=queue;self.head=head
 end
 local count=0
 while self.head<=#self.queue and count<128 do
  local row=self.queue[self.head];self.queue[self.head]=false;self.head=self.head+1;count=count+1
  local ok,value,why=pcall(self._handle,self,row,b,pc)
  if not ok or value==false then self.stats.rejected=self.stats.rejected+1;self.faults[#self.faults+1]=tostring(not ok and value or why)end
 end
 if self.head>#self.queue then self.queue={};self.head=1 end
 local ok,err=pcall(self._progress,self,pc,input)
 if not ok then self.faults[#self.faults+1]=tostring(err);if self.tx then pcall(self._abort,self,tostring(err))end end
 return self:status()
end
function Client:stop(reason,context_alive)
 self.stopped=true;return self:reset(reason or'travel_client_stopped',context_alive)
end
function Client:status()
 local tx=self.tx;local phase=tx and tx.phase or'idle'
 return{v=1,stopped=self.stopped==true,phase=phase,blocked=phase~='idle'and phase~='complete'and phase~='error',active=tx and tx._applied or false,
  tx=tx and tx.tx,dim=tx and tx.dim,view=tx and tx.view,world_session=tx and tx.world_session,mapping=self.mapping,
  error=tx and tx.error,waiting=tx and tx.waiting,stats=self.P.copy(self.stats),faults=self.P.copy(self.faults),
  prepare_deadline=tx and tx.deadline,initial_prepare_limit=tx and tx.initial_prepare_limit,
  initial_prepare_extensions=tx and tx.initial_prepare_extensions}
end
return M
