-- Authoritative Pal travel executor. No autostart; observe is data-only, tick is game-thread only.
-- MC owns vanilla portal/end/respawn decisions. Clients can report readiness, never choose a destination.
local dir=assert(debug.getinfo(1,'S').source:match('^@(.*[/\\])'))
local M={version=1};local Server={};Server.__index=Server
local function dep(o,name)return o[name]or dofile((o.module_dir or dir..'../travel/')..name..'.lua')end
local function saved(value)
 if type(value)~='table'then return value end;local out={}
 for k,v in pairs(value)do if type(k)~='string'or k:sub(1,1)~='_'then out[k]=saved(v)end end;return out
end
function M.new(o)
 assert(o and o.resolve and o.send and o.journal and o.view,'travel_server_dependencies_required')
 local P=dep(o,'protocol');local c=o.config or dep(o,'config');local checkpoint=o.journal.load()or{}
 local self=setmetatable({options=o,P=P,config=c,world_session=checkpoint.world_session,last_seq=checkpoint.last_seq or 0,
  retired=checkpoint.retired or{},players=checkpoint.players or{},pending=checkpoint.pending or{},counter=checkpoint.counter or 0,
  queue={},queue_head=1,stats={begun=0,moved=0,completed=0,recovered=0,rejected=0,errors=0},faults={}},Server)
 self.registry=P.registry(c,checkpoint.registry)
 if o.view.can_recycle then self.registry.can_recycle=function(mapping)
  return o.view.can_recycle(mapping.region_id,{world_session=mapping.world_session})==true
 end end
 self.actor=o.actor or dep(o,'actor').new{protocol=P,config=c,readers=o.readers,game_thread=o.game_thread,
  verify_identity=o.verify_identity,streaming_ready=o.streaming_ready}
 for uid,player in pairs(self.players)do self.registry:retain(player.mapping,'active:'..uid);player._needs_recover=true end
 for _,tx in pairs(self.pending)do
  if tx.phase~='complete'and tx.phase~='error'and tx.phase~='superseded'then self.registry:retain(tx.mapping,'tx:'..tx.tx)end
  tx._needs_recover=true
 end
 -- Same-UWorld reload can hand the occupied scene back to the new executor without dropping its floor.
 for _,scene in ipairs(o.recovery_scenes or{})do
  local tx=self.pending[scene.pal_uid];local player=self.players[scene.pal_uid]
  if tx and tx.phase~='complete'and tx.mapping.region_id==scene.mapping.region_id then tx._ticket=scene.ticket
  elseif player and player.mapping.region_id==scene.mapping.region_id then player._ticket=scene.ticket end
 end
 return self
end
function Server:_thread()
 local check=self.options.game_thread or IsInGameThread
 assert(type(check)=='function'and check()==true,'travel_requires_game_thread')
end
function Server:_save()
 local ok,result=pcall(self.options.journal.save,{v=1,world_session=self.world_session,last_seq=self.last_seq,retired=self.retired,
  counter=self.counter,registry=self.registry:save(),players=saved(self.players),pending=saved(self.pending)})
 if not ok or result~=true then self._journal_fault=tostring(not ok and result or'travel_journal_failed');error(self._journal_fault)end
end
function Server:_send(tx,phase,extra)
 local row=self.P.message(tx,phase,extra);assert(self.options.send(row)==true,'travel_server_send_failed');tx._last_send=self.now
 return row
end
function Server:_prepare_message(tx)
 return self:_send(tx,'prepare',{mapping=tx.mapping,required_bounds=tx.required_bounds,pos=tx.pos,yaw=tx.yaw,pitch=tx.pitch,
  target_pawn=tx.target_pawn,from=tx.source and tx.source.dim,recovering=tx.recovering==true})
end
function Server:_resolve(player)
 local b=self.options.resolve(player)
 if not b then return nil,'authenticated_player_unavailable'end
 if not self.P.binding(b)or b.mc_uuid~=player then return nil,'authenticated_binding_invalid'end
 local ok,why=self.actor.valid(b.pc,b,true);if not ok then return nil,why end;return b
end
function Server:_release_ticket(ticket,mapping,owner)
 if ticket then assert(self.options.view.release(ticket)==true,'native_view_release_failed')end
 self.registry:release(mapping,owner)
end
function Server:_cancel(tx,reason)
 -- Once a move may have happened, only a measured forward recovery may resolve it.
 if tx.phase=='moving'or tx.phase=='committed'or tx.phase=='finalizing'or tx.phase=='recovery_required'then return self:_recovery(tx,reason)end
 tx.phase='error';tx.error=reason;self:_save()
 if tx._lock then self.actor.release(tx._lock);tx._lock=nil end
 self:_release_ticket(tx._ticket,tx.mapping,'tx:'..tx.tx);tx._ticket=nil
 local restore
 if tx.source and tx.source.mapping then
  local pos=self.P.copy(tx.source.snapshot.position);pos.Z=pos.Z-tx.source.snapshot.half_height
  local r=tx.source.snapshot.rotation
  restore={dim=tx.source.dim,pos=self.P.to_mc(tx.source.mapping,pos),yaw=-90-r.Yaw,pitch=-r.Pitch}
 end
 self:_send(tx,'error',{error=reason,applied=false,needs_mc_rollback=restore~=nil,restore=restore})
 if self.options.abort_world then assert(self.options.abort_world(self.P.message(tx,'error',{
  applied=false,error=reason,needs_mc_rollback=restore~=nil,restore=restore}))==true,'travel_abort_publish_failed')end
end
function Server:_recovery(tx,reason)
 tx.phase='recovery_required';tx.error=reason;tx.recovering=true;self:_save()
 self:_send(tx,'recovery_required',{error=reason,applied=false,mapping=tx.mapping,target_pawn=tx.target_pawn})
end
function Server:_adopt_interrupted(tx)
 -- A newer vanilla transition/respawn may supersede an unfinished one. Retain its actual occupied scene.
 local at=self.actor.position(tx._pc);local near=self.P.distance(at,tx.target_pawn)<=self.config.position_tolerance_cm
 local target_region=self.P.contains(tx.mapping.region_bounds,at)
 local source_region=tx.source and tx.source.mapping and self.P.contains(tx.source.mapping.region_bounds,at)
 if near or(target_region and not source_region)then
  local uid=tx.binding.pal_uid;local previous=self.players[uid]
  self.registry:retain(tx.mapping,'active:'..uid)
  self.players[uid]={binding=tx.binding,mapping=tx.mapping,dim=tx.dim,world_session=tx.world_session,view=tx.view,
   pos=tx.pos,yaw=tx.yaw,pitch=tx.pitch,_ticket=tx._ticket}
  if previous and previous.mapping.region_id~=tx.mapping.region_id then
   self:_release_ticket(previous._ticket,previous.mapping,'active:'..uid)
  end
  self.registry:release(tx.mapping,'tx:'..tx.tx);tx._ticket=nil
 else
  local source=tx.source and tx.source.snapshot
  assert(source and(self.P.distance(at,source.position)<=self.config.position_tolerance_cm or source_region),'ambiguous_interrupted_pal_position')
  self:_release_ticket(tx._ticket,tx.mapping,'tx:'..tx.tx);tx._ticket=nil
 end
 if tx._lock then self.actor.release(tx._lock);tx._lock=nil end
 tx.phase='superseded';self.pending[tx.binding.pal_uid]=nil;self:_save()
end
function Server:_begin(row,e,b)
 local P=self.P;local uid=b.pal_uid;local old=self.pending[uid];local current=self.players[uid]
 if old and old._rebase_lock and(row.session~=old.world_session or e.view>old.view)then
  self.actor.release(old._rebase_lock);old._rebase_lock=nil
 end
 if old then
  if old.phase=='complete'and old._needs_recover then self.pending[uid]=nil;old=nil end
 end
 if old then
  if old.world_session==row.session and old.view==e.view and P.same_binding(old.binding,b)and old.dim==e.to then
   if old.phase=='complete'then self:_send(old,'complete',old.final)
   elseif old.phase=='error'then self:_send(old,'error',{error=old.error,applied=false})
   elseif old._needs_recover then self:_resume(old,b)
   elseif old.phase=='committed'or old.phase=='finalizing'then self:_send(old,'committed',{mapping=old.mapping,target_pawn=old.server_position or old.target_pawn})
   else self:_prepare_message(old)end
   return true
  end
  if old.world_session==row.session and e.view<old.view then return false,'stale_view'end
  if old.phase=='moving'or old.phase=='committed'or old.phase=='finalizing'or old.phase=='recovery_required'then
   old._pc=b.pc;self:_adopt_interrupted(old)
  elseif old.phase~='error'and old.phase~='complete'then self:_cancel(old,'superseded')end
  current=self.players[uid]
 end
 if current and current.world_session==row.session and e.view<current.view then return false,'stale_view'end
 if current and current.world_session==row.session and e.view==current.view and current.dim~=e.to then return false,'view_dimension_conflict'end
 if current and e.from and current.dim~=e.from and not(e.reason=='rollback'and current.dim==e.to)then return false,'source_dimension_mismatch'end
 if current and current.world_session==row.session and current.view==e.view and P.same_binding(current.binding,b)and not current._needs_recover then
  return true,'already_applied'
 end
 self.counter=self.counter+1
 local txid=b.session_id..':'..row.session..':'..e.view..':'..self.counter
 local mapping,err
 if e.reason=='rollback'and current and current.dim==e.to and current.mapping.world_session==row.session
  and self.registry:required(current.mapping,e.pos)then
  -- A failed physical rebase restores the logical pose on its already occupied source arena.
  -- Canonical allocation would otherwise choose the same failed new arena again.
  mapping=P.copy(current.mapping);self.registry:retain(mapping,'tx:'..txid)
 else mapping,err=self.registry:acquire(row.session,e.to,e.pos,'tx:'..txid)end
 if not mapping then
  self:_intent_error(row,e,b,txid,err,current);return false,err
 end
 local bounds,why=self.registry:required(mapping,e.pos)
 if not bounds then
  self.registry:release(mapping,'tx:'..txid);self:_intent_error(row,e,b,txid,why,current);return false,why
 end
 local snapshot=self.actor.snapshot(b.pc);local target=P.to_ue(mapping,e.pos);target.Z=target.Z+snapshot.half_height
 local tx={tx=txid,binding=P.identity(b),world_session=row.session,view=e.view,dim=e.to,reason=e.reason,
  phase='preparing',mapping=mapping,required_bounds=bounds,pos=P.copy(e.pos),yaw=e.yaw,pitch=e.pitch,target_pawn=target,
  source={mapping=current and current.mapping,dim=current and current.dim,snapshot=snapshot},started=self.now,
  deadline=self.now+self.config.prepare_timeout_ms,_pc=b.pc,_source_ticket=current and current._ticket,
  _already_arrived=P.distance(snapshot.position,target)<=self.config.position_tolerance_cm}
 if mapping.native_overworld and(e.reason=='join'or e.reason=='reconnect'or e.reason=='respawn')
  and(not current or current.world_session~=row.session or not P.same_binding(current.binding,b))then
  tx.initial_prepare_started=self.now;tx.initial_prepare_limit=self.now+math.max(self.config.prepare_timeout_ms,180000)
 end
 self.pending[uid]=tx;self:_save() -- Durable intent before locks, actor creation, or travel messages.
 self:_start_prepare(tx,b);self.stats.begun=self.stats.begun+1;return true
end
function Server:_intent_error(row,e,b,txid,reason,current)
 local tx={tx=txid,binding=self.P.identity(b),world_session=row.session,dim=e.to,view=e.view}
 local restore=current and{dim=current.dim,pos=current.pos,yaw=current.yaw,pitch=current.pitch}or nil
 local out=self:_send(tx,'error',{error=reason,applied=false,needs_mc_rollback=current~=nil,restore=restore})
 if self.options.abort_world then assert(self.options.abort_world(out)==true,'travel_abort_publish_failed')end
end
function Server:_start_prepare(tx,b)
 tx._pc=b.pc;tx._needs_recover=nil;tx.started=self.now;tx.deadline=self.now+self.config.prepare_timeout_ms
 tx._pawn_address=self.actor.snapshot(b.pc).pawn_address
 tx._lock=self.actor.hold(b.pc,true,tx.recovering and tx.source.snapshot or nil)
 if tx.mapping.auxiliary_pending and self.options.allow_aux_overworld~=true then
  self:_cancel(tx,'auxiliary_overworld_pending_validation');return
 end
 local ok,safe,detail=pcall(self.actor.safety,b.pc,tx.mapping,tx.target_pawn,b)
 if not ok then self:_cancel(tx,'pal_preflight_exception:'..tostring(safe));return end
 if safe~=true then self:_cancel(tx,detail);return end;tx.safety=detail
 local prepared,ticket=pcall(self.options.view.prepare_view,self.P.request(tx,'server'))
 if not prepared or not ticket then self:_cancel(tx,'native_target_prepare_failed:'..tostring(ticket));return end
 tx._ticket=ticket
 tx.phase='preparing';tx.error=nil;self:_save();self:_prepare_message(tx)
end
function Server:_resume(tx,b)
 -- Replay a persisted MOVING intent only after comparing the actual authority pawn, never by the old return value.
 local P=self.P;local oldbinding=tx.binding
 if tx._lock then self.actor.release(tx._lock);tx._lock=nil end
 if tx._ticket then assert(self.options.view.release(tx._ticket)==true,'recovery_view_release_failed');tx._ticket=nil end
 local oldid=tx.tx;self.counter=self.counter+1
 tx.tx=b.session_id..':'..tx.world_session..':'..tx.view..':'..self.counter
 self.registry:retain(tx.mapping,'tx:'..tx.tx);self.registry:release(tx.mapping,'tx:'..oldid)
 if not P.same_binding(oldbinding,b)then
  tx.binding=P.identity(b);tx.client_ready=nil;tx.client_observed=nil
  if tx.mapping.native_overworld then
   tx.initial_prepare_started=self.now;tx.initial_prepare_limit=self.now+math.max(self.config.prepare_timeout_ms,180000)
   tx._initial_prepare_progress=nil;tx._initial_prepare_progress_at=nil
  end
 end
 local at=self.actor.position(b.pc);local target=P.distance(at,tx.target_pawn)<=self.config.position_tolerance_cm
 local source=tx.source and tx.source.snapshot
 local known_region=P.contains(tx.mapping.region_bounds,at)or(tx.source and tx.source.mapping and P.contains(tx.source.mapping.region_bounds,at))
 if tx.phase=='moving'and not target and(not source or P.distance(at,source.position)>self.config.position_tolerance_cm)and not known_region then
  tx._pc=b.pc;tx._needs_recover=nil;self:_recovery(tx,'ambiguous_crash_position');return
 end
 tx.recovering=true;tx._already_arrived=target;tx.server_position=target and at or nil
 tx.client_ready=nil;tx.client_observed=nil;self:_save();self:_start_prepare(tx,b);self.stats.recovered=self.stats.recovered+1
end
function Server:observe_world(row)
 if self.stopped then return false,'travel_server_stopped'end
 if type(row)~='table'or row.t~='blocks'or row.v~=2 then return false,'world_envelope'end
 local events={};for _,e in ipairs(row.lifecycle or{})do if e.op=='player_view'then
  local ok,why=self.P.event(row,e);if not ok then self.stats.rejected=self.stats.rejected+1;return false,why end
  events[#events+1]=self.P.copy(e)
 end end
 if #events==0 then return true end
 if #self.queue-self.queue_head>=1024 then return false,'travel_queue_full'end
 self.queue[#self.queue+1]={kind='world',row={t='blocks',v=2,session=row.session,seq=row.seq,dim=row.dim},events=events};return true
end
function Server:observe_client(row,binding)
 if self.stopped then return false,'travel_server_stopped'end
 -- Caller supplies binding derived from the authenticated transport, never row.pal_uid.
 if not self.P.envelope(row)or not self.P.binding(binding)then return false,'authenticated_client_message_required'end
 if row.phase~='client_ready'and row.phase~='client_observed'and row.phase~='client_abort'then return false,'client_phase'end
 self.queue[#self.queue+1]={kind='client',row=self.P.copy(row),binding=self.P.identity(binding)};return true
end
function Server:_world(item)
 local row=item.row
 if self.retired[row.session]then return true,'retired_world_session'end
 if self.world_session~=row.session then
  if self.world_session then self.retired[self.world_session]=true end
  self.world_session=row.session;self.last_seq=0
 end
 if row.seq<=self.last_seq and not item.deferred then return true,'duplicate_world_row'end
 for _,e in ipairs(item.events)do
  local b,why=self:_resolve(e.player)
  if not b then return false,why end
  local ok,err=self:_begin(row,e,b);if not ok then self.stats.rejected=self.stats.rejected+1;self.faults[e.player]=err end
 end
 self.last_seq=math.max(self.last_seq,row.seq);self:_save();return true
end
function Server:_client(item)
 local row=item.row;local tx=self.pending[item.binding.pal_uid]
 if not tx or not self.P.same_binding(tx.binding,item.binding)or not self.P.matches(row,tx,item.binding)then return false,'stale_client_message'end
 local fresh,err=self:_resolve(tx.binding.mc_uuid)
 if not fresh or not self.P.same_binding(fresh,tx.binding)then return false,err or'outer_session_changed'end
 if row.phase=='client_ready'then
  local ready,why=self.P.ready(row.proof,self.P.request(tx,'client'),'client');if not ready then return false,why end
  if tx.phase~='preparing'and tx.phase~='committed'and tx.phase~='finalizing'then return false,'ready_out_of_phase'end
  tx.client_ready=self.P.copy(row.proof);self:_save()
 elseif row.phase=='client_observed'then
  if tx.phase~='committed'and tx.phase~='finalizing'then return false,'observed_before_server_commit'end
  if not self.P.ue(row.position)or self.P.distance(row.position,tx.server_position)>self.config.position_tolerance_cm
   or row.region_id~=tx.mapping.region_id then return false,'client_replication_position_mismatch'end
  local ready,why=self.P.ready(row.proof,self.P.request(tx,'client'),'client');if not ready then return false,why end
  local published,detail=self.P.camera_commit(row.proof.camera_commit,tx)
  if not published then return false,detail end
  tx.client_ready=self.P.copy(row.proof)
  tx.client_observed=self.P.copy(row.position);self:_save()
 else self:_cancel(tx,row.error or'client_abort')end
 return true
end
function Server:_move(tx)
 local P=self.P;local b,err=self:_resolve(tx.binding.mc_uuid)
 if not b or not P.same_binding(tx.binding,b)then return self:_cancel(tx,err or'outer_session_changed')end
 if b.pc:GetAddress()~=tx._pc:GetAddress()or self.actor.snapshot(b.pc).pawn_address~=tx._pawn_address then
  return self:_cancel(tx,'possession_changed')
 end
 local safe,why=self.actor.safety(b.pc,tx.mapping,tx.target_pawn,b);if not safe then return self:_cancel(tx,why)end
 assert(self.options.view.activate(tx._ticket)==true,'native_server_activation_failed')
 tx.phase='moving';self:_save() -- Write-ahead record: an exception/false return can still follow a side effect.
 local arrived=tx._already_arrived
 if not arrived then
  local ok,detail=self.actor.teleport(b.pc,tx.target_pawn,P.mc_rotation(tx.yaw,tx.pitch))
  if not ok then
   local at=self.actor.position(b.pc)
   if P.distance(at,tx.source.snapshot.position)<=self.config.position_tolerance_cm then tx.phase='preparing';return self:_cancel(tx,detail)end
   return self:_recovery(tx,detail or'teleport_failed_after_move')
  end
  self.stats.moved=self.stats.moved+1
 end
 local at=self.actor.position(b.pc)
 if P.distance(at,tx.target_pawn)>self.config.position_tolerance_cm then return self:_recovery(tx,'server_landing_position_mismatch')end
 tx.server_position=at;tx.phase='committed';tx.committed_at=self.now;tx.deadline=self.now+self.config.replication_timeout_ms
 self:_save();self:_send(tx,'committed',{mapping=tx.mapping,target_pawn=at})
end
function Server:_finalize(tx)
 local P=self.P;local at=self.actor.position(tx._pc)
 if P.distance(at,tx.server_position)>self.config.position_tolerance_cm then return self:_recovery(tx,'server_position_drift')end
 local safe,why=self.actor.safety(tx._pc,tx.mapping,at,tx.binding);if not safe then return self:_recovery(tx,why)end
 local server_proof=self.options.view.readiness(tx._ticket)
 local sr,detail=P.ready(server_proof,P.request(tx,'server'),'server')
 if not sr then return self:_recovery(tx,detail)end
 local proof={server_position=at,client_position=tx.client_observed,target_pawn=tx.target_pawn,
  server_revision=server_proof.revision,client_revision=tx.client_ready.revision,
  collision_committed=true,visual_committed=true,camera_commit=tx.client_ready.camera_commit,server_settle_ms=self.now-tx.committed_at}
 local final=P.message(tx,'complete',{operation='world_view_ack',applied=true,authority_source='pal_server',mapping=tx.mapping,proof=proof})
 tx.phase='finalizing';tx.final=final;self:_save()
 assert(self.options.journal.ack(final)==true,'authoritative_ack_publish_failed')
 local uid=tx.binding.pal_uid;local old=self.players[uid]
 self.registry:retain(tx.mapping,'active:'..uid)
 self.players[uid]={binding=tx.binding,mapping=tx.mapping,dim=tx.dim,world_session=tx.world_session,view=tx.view,
  pos=tx.pos,yaw=tx.yaw,pitch=tx.pitch,_ticket=tx._ticket}
 tx.phase='complete';self:_save()
 if tx._lock then self.actor.release(tx._lock);tx._lock=nil end
 if old then
  if old._ticket and old._ticket~=tx._ticket then assert(self.options.view.release(old._ticket)==true,'native_source_release_failed')end
  if old.mapping.region_id~=tx.mapping.region_id then self.registry:release(old.mapping,'active:'..uid)end
 end
 self.registry:release(tx.mapping,'tx:'..tx.tx);self:_send(tx,'complete',final);self.stats.completed=self.stats.completed+1
end
function Server:_progress(tx)
 if self._journal_fault or tx._fault then return end
 if tx.phase=='error'or tx.phase=='superseded'then return end
 if tx.phase=='complete'then return end
 if tx.world_session~=self.world_session then
  if tx.phase~='complete'and tx.phase~='recovery_required'then return self:_recovery(tx,'world_session_changed')end;return
 end
 local b,why=self:_resolve(tx.binding.mc_uuid)
 if not b then
  if tx.phase=='preparing'then
   if why=='authenticated_player_unavailable'and self.now<tx.deadline then tx._waiting=why;return end
   return self:_cancel(tx,why)
  end
  if tx.phase~='complete'and tx.phase~='recovery_required'then return self:_recovery(tx,why)end;return
 end
 if tx._needs_recover or not self.P.same_binding(tx.binding,b)then return self:_resume(tx,b)end
 if tx.phase=='recovery_required'then return end
 if tx.phase=='complete'then return end
 if tx.phase=='preparing'then
  local request=self.P.request(tx,'server');request.generation=tx._ticket and tx._ticket.generation
  local proof=self.options.view.readiness(tx._ticket)
  local ready,detail=self.P.ready(proof,request,'server')
  local extended=self.P.initial_prepare_lease(tx,proof,request,self.now,self.config.prepare_timeout_ms,'server')
  if extended then self:_save()end
  if self.now>=tx.deadline then return self:_cancel(tx,'target_prepare_timeout')end
  tx._waiting=detail
  if ready then tx.server_ready=self.P.copy(proof)end
  if ready and tx.client_ready then return self:_move(tx)end
  if not tx._last_send or self.now-tx._last_send>=self.config.resend_ms then self:_prepare_message(tx)end
 elseif tx.phase=='committed'or tx.phase=='finalizing'then
  if self.now>=tx.deadline then return self:_cancel(tx,'client_replication_timeout')end
  if tx.client_observed and self.now-tx.committed_at>=self.config.server_settle_ms then return self:_finalize(tx)end
  if not tx._last_send or self.now-tx._last_send>=self.config.resend_ms then self:_send(tx,'committed',{mapping=tx.mapping,target_pawn=tx.server_position})end
 end
end
function Server:tick(now)
 self:_thread();assert(type(now)=='number'and now==now,'monotonic_time_required');self.now=now
 if self.stopped then return self:status()end
 local count=0;local last=#self.queue
 while self.queue_head<=last and count<128 do
  local item=self.queue[self.queue_head];local ok,result,detail=pcall(item.kind=='world'and self._world or self._client,self,item)
  self.queue[self.queue_head]=false;self.queue_head=self.queue_head+1;count=count+1
  if item.kind=='world'and ok and result==false and detail=='authenticated_player_unavailable'then
   item.deferred=true;self.queue[#self.queue+1]=item
  elseif not ok or result==false then self.stats.rejected=self.stats.rejected+1;self.faults['queue']=tostring(not ok and result or detail)end
 end
 if self.queue_head>#self.queue then self.queue={};self.queue_head=1 end
 if self.queue_head>512 then
  local rest={};for i=self.queue_head,#self.queue do rest[#rest+1]=self.queue[i]end;self.queue=rest;self.queue_head=1
 end
 for _,tx in pairs(self.pending)do
  local ok,err=pcall(self._progress,self,tx)
  if not ok then self.stats.errors=self.stats.errors+1;self.faults[tx.binding.mc_uuid]=tostring(err)
   -- A write failure before MOVING must never permit a later unjournalled retry to move.
   tx._fault=tostring(err)
   if tx.phase=='moving'then pcall(self._recovery,self,tx,'teleport_exception:'..tostring(err))end
  end
 end
 if not self._journal_fault then
  local ok,why=pcall(self.check_boundaries,self,now)
  if not ok then self.faults.boundary=tostring(why)end
 end
 return self:status()
end
function Server:check_boundaries(now)
 self:_thread();self.now=now or self.now
 if self.stopped or self._journal_fault or(self._next_boundary and self.now<self._next_boundary)then return false end
 self._next_boundary=self.now+(self.config.boundary_poll_ms or 500)
 for uid,player in pairs(self.players)do
  local tx=self.pending[uid]
  if tx and tx.phase=='complete'and player.world_session==self.world_session and not player.mapping.native_overworld then
   local b=self:_resolve(player.binding.mc_uuid)
   if b and self.P.same_binding(b,player.binding)then
    local snapshot=self.actor.snapshot(b.pc);local feet=self.P.copy(snapshot.position);feet.Z=feet.Z-snapshot.half_height
    local pos=self.P.to_mc(player.mapping,feet);local page=self.config.page_blocks
    local ax=math.floor((pos[1]+page/2)/page)*page;local az=math.floor((pos[3]+page/2)/page)*page
    local crossed=ax~=player.mapping.mc_anchor[1]or az~=player.mapping.mc_anchor[3]
    if crossed then
     if self.options.rebase_supported~=true then
      self.faults[player.binding.mc_uuid]='mc_rebase_hook_unavailable'
      -- Protect the pawn at the actual outer allocation boundary; never let an absent transport look successful.
      if not self.P.contains(player.mapping.region_bounds,snapshot.position,snapshot.half_height+200)and not tx._rebase_lock then
       tx._rebase_lock=self.actor.hold(b.pc,true)
      end
     else
      if not tx._rebase_lock then tx._rebase_lock=self.actor.hold(b.pc,true)end
      if not tx._rebase_sent or self.now-tx._rebase_sent>=(self.config.rebase_resend_ms or 1000)then
       self:_send(tx,'rebase_required',{applied=false,mc_pos=pos,reason='physical_region_window',region_id=player.mapping.region_id,
        source_position=snapshot.position,next_mc_anchor={ax,self.config.y_origin,az}})
       tx._rebase_sent=self.now
      end
     end
    end
   end
  end
 end
 return true
end
function Server:retry(player)
 self:_thread();self._journal_fault=nil;self:_save()
 if self.stopped then return false,'travel_server_stopped'end
 local b,why=self:_resolve(player);if not b then return false,why end
 local tx=self.pending[b.pal_uid];if not tx then return false,'no_pending_travel'end
 if tx.world_session~=self.world_session then return false,'retired_world_session'end
 tx._fault=nil;self:_resume(tx,b);return true
end
function Server:stop(reason,context_alive)
 self:_thread();self.stopped=true;local retained={};local abandoned={}
 for uid,tx in pairs(self.pending)do
  local occupied=tx.phase=='moving'or tx.phase=='committed'or tx.phase=='finalizing'or tx.phase=='recovery_required'or tx.phase=='complete'
  if tx.phase~='complete'and tx.phase~='error'and tx.phase~='superseded'then
   tx.error=reason or'travel_runtime_stopped';tx.recovering=occupied;tx._needs_recover=true
   if occupied then tx.phase='recovery_required'end
  end
  if context_alive~=false then
   if tx._lock then self.actor.release(tx._lock);tx._lock=nil end
   if tx._rebase_lock then self.actor.release(tx._rebase_lock);tx._rebase_lock=nil end
   if tx._ticket and not occupied then self:_release_ticket(tx._ticket,tx.mapping,'tx:'..tx.tx);tx._ticket=nil end
  else
   tx._lock=nil;tx._rebase_lock=nil
   if tx._ticket then assert(self.options.view.abandon and self.options.view.abandon(tx._ticket)==true,'stale_server_scene_abandon_required');abandoned[tx._ticket]=true;tx._ticket=nil end
  end
  if context_alive~=false and tx._ticket then retained[#retained+1]={player=tx.binding.mc_uuid,pal_uid=uid,mapping=tx.mapping,ticket=tx._ticket,occupied=true}end
 end
 for uid,p in pairs(self.players)do if p._ticket then
  local duplicate=false;for _,scene in ipairs(retained)do if scene.ticket==p._ticket then duplicate=true end end
  if context_alive==false then
   if not abandoned[p._ticket]then assert(self.options.view.abandon and self.options.view.abandon(p._ticket)==true,'stale_server_scene_abandon_required')end;p._ticket=nil
  elseif not duplicate then retained[#retained+1]={player=p.binding.mc_uuid,pal_uid=uid,mapping=p.mapping,ticket=p._ticket,occupied=true}end
 end end
 self:_save();self.retained_scene_count=#retained
 if self.options.retain_scene then for _,scene in ipairs(retained)do assert(self.options.retain_scene(scene)==true,'occupied_scene_handoff_failed')end end
 return true,{retained_scenes=retained,reason=reason or'travel_runtime_stopped',context_alive=context_alive~=false}
end
function Server:status()
 local players={};for uid,tx in pairs(self.pending)do players[uid]={player=tx.binding.mc_uuid,phase=tx.phase,dim=tx.dim,view=tx.view,
  world_session=tx.world_session,tx=tx.tx,region_id=tx.mapping.region_id,error=tx.error,waiting=tx._waiting,fault=tx._fault,
  prepare_deadline=tx.deadline,initial_prepare_limit=tx.initial_prepare_limit,initial_prepare_extensions=tx.initial_prepare_extensions}end
 return{v=1,stopped=self.stopped==true,retained_scene_count=self.retained_scene_count or 0,
  rebase_supported=self.options.rebase_supported==true,auxiliary_overworld_enabled=self.options.allow_aux_overworld==true,
  world_session=self.world_session,players=players,queued=#self.queue-self.queue_head+1,
  stats=self.P.copy(self.stats),faults=self.P.copy(self.faults),runtime_validation=self.config.validation}
end
return M
