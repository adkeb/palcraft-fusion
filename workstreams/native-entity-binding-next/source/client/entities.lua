-- Observer only. Native Pal bodies are real replicated actors; this client never spawns combat bodies or sends damage.
local E={}
local function live(a)return a and a:IsValid()and not a:GetFullName():find('Default__',1,true)end
local function guid(g)
 return('%08x-%04x-%04x-%04x-%04x%08x'):format(g.A&0xffffffff,(g.B>>16)&0xffff,g.B&0xffff,(g.C>>16)&0xffff,g.C&0xffff,g.D&0xffffffff)
end
function E.new(o)
 assert(IsInGameThread(),'Entity observer must run on game thread')
 local J=assert(o.json);local root=assert(o.root):gsub('\\','/'):gsub('/?$','/')
 local now=o.now or os.time
 local realm=o.local_realm;local realm_scope
 local function pin_realm(proof)
  realm_scope={mode=proof.mode,server_session_id=proof.server_session_id,realm_generation=proof.realm_generation,
   world_address=proof.world_address,world_id=proof.world_id,host_uid=proof.host_uid,
   world_save_root=proof.world_save_root,process_epoch=proof.process_epoch}
 end
 if realm then
  local proof,why=realm:current()
  if proof then
   assert(proof.mode=='standalone'and realm:validate(proof)==true,'Verified entity local realm required: '..tostring(why))
   assert(proof.server_session_id==o.session and proof.world_id==o.world_id and proof.host_uid==o.player_uid,
    'Entity host identity differs from actual local realm')
   pin_realm(proof)
  end
 end
 local M={running=true,views={},revision=-1,pending_models=true,phase='waiting_for_authority'};local actor_bindings={}
 local function read(name)
  if o.read then return o.read(name)end
  local f=io.open(root..name,'rb');if not f then return end;local raw=f:read('*a');f:close();assert(#raw<=1048576,'Observer snapshot too large');return J.decode(raw)
 end
 local function fresh(q)return q and type(q.unix)=='number'and now()-q.unix>=-5 and now()-q.unix<=3 end
 local function session(pc)
  if realm then
   if not realm_scope then
    local proof=realm:current()
    if not proof or proof.mode~='standalone'or proof.server_session_id~=o.session
     or proof.world_id~=o.world_id or proof.host_uid~=o.player_uid or realm:validate(proof,pc)~=true then return end
    pin_realm(proof)
   end
   if realm:validate(realm_scope,pc)==true then return realm_scope.server_session_id end
   return
  end
  for _,g in ipairs(FindAllOf('PalGameStateInGame')or{})do if live(g)then local id=type(g.ServerSessionId)=='string'and g.ServerSessionId or g.ServerSessionId:ToString();if id==o.session then return id end end end
 end
 local function clear_views(context_alive)
  if o.renderer then for _,v in pairs(M.views)do if v.render_handle then o.renderer.remove(v.render_handle,context_alive)end end end
  M.views={};M.rendered=0;M.pending_models=true;actor_bindings={}
 end
 function M.verify_actor(row,actor)
  local binding=actor_bindings[row.id]
  return M.running and binding~=nil and binding.row==row and binding.row.dimension==row.dimension
   and binding.actor==actor and live(actor)and actor:GetAddress()==binding.address
 end
 function M.tick(pc)
  assert(IsInGameThread(),'Observer tick must run on game thread')
  if not M.running then return end
  if not live(pc)or not session(pc)then clear_views(false);M.phase='other_or_unloaded_session';return end
  local state=read('mc-state.json');local pal=read('pal-state.json')
  if not fresh(state)or not fresh(pal)or state.session~=o.session or pal.session~=o.session then clear_views();M.phase='authority_stale';return end
  local actors={};local utility=StaticFindObject('/Script/Pal.Default__PalUtility')
  for _,a in ipairs(FindAllOf('PalCharacter')or{})do
   if live(a)and utility and utility:IsValid()then
    local good,id=pcall(function()
     local cp=a:GetCharacterParameterComponent();local ip=cp:GetIndividualParameter();local manager=utility:GetCharacterManager(a)
     local handle=manager:GetIndividualHandleFromCharacterParameter(ip);local value=handle:GetIndividualID()
     return 'pal:'..guid(value.PlayerUId)..'/'..guid(value.InstanceId)
    end)
    if good then actors[id]=a end
   end
  end
  local bindings={}
  for _,b in ipairs(pal.bodies or{})do if b.source_epoch==state.epoch and b.body_epoch==pal.epoch and b.phase=='active'then bindings[b.id]=b end end
  -- Publish the actual current snapshot/native_id/Actor pairing BEFORE calling
  -- the captured renderer, including the first spawn. No nearest-Actor lookup.
  actor_bindings={}
  for _,r in ipairs(state.entities or{})do
   if r.category=='mob'and(r.alive or(r.death_time or 0)>0 and(r.death_time or 0)<=20)then
    local b=bindings[r.id];local a=b and b.dimension==r.dimension and actors[b.native_id]
    if a then actor_bindings[r.id]={row=r,actor=a,address=a:GetAddress(),native_id=b.native_id,body_epoch=pal.epoch}end
   end
  end
  local next_views={};local rendered=0
  for _,r in ipairs(state.entities or{})do
   if r.category=='mob'and(r.alive or(r.death_time or 0)>0 and(r.death_time or 0)<=20)then
    local binding=bindings[r.id];local a=binding and binding.dimension==r.dimension and actors[binding.native_id]
    if a then
     local prior=M.views[r.id]
     if prior and prior.render_handle and(prior.native_id~=binding.native_id or prior.body_epoch~=pal.epoch
      or not live(prior.actor)or prior.actor:GetAddress()~=a:GetAddress())then
      o.renderer.remove(prior.render_handle);prior=nil
     end
     local view={id=r.id,kind=r.kind,actor=a,state=r,native_id=binding.native_id,body_epoch=pal.epoch,render='native_pal_surrogate_pending_mc_model'}
     -- A renderer may be supplied by the native owner only when it implements real world meshes/animations.
     if o.renderer then
      local handle=prior and prior.render_handle or o.renderer.spawn(r,a)
      if handle then
       local ready=o.renderer.update(handle,r,a);view.render_handle=handle
       if ready~=false then view.render='mc_world_model';rendered=rendered+1 end
      end
     end
     next_views[r.id]=view
    end
   end
  end
  if o.renderer then for id,v in pairs(M.views)do if not next_views[id]and v.render_handle then o.renderer.remove(v.render_handle)end end end
  M.views=next_views;M.revision=state.revision;M.phase='observing_native_bodies';M.rendered=rendered
  local n=0;for _ in pairs(next_views)do n=n+1 end;M.pending_models=not o.renderer or rendered<n
 end
 function M.vitals(pc)
  if not live(pc)or not session(pc)then return {ok=false,status='unloaded_or_other_session'}end
  local uid=guid(pc:GetPlayerUId());local pal=read('pal-state.json');local mc=read('mc-state.json')
  if not fresh(pal)or not fresh(mc)or pal.session~=o.session or mc.session~=o.session then return {ok=false,player_uid=uid,status='authority_stale'}end
  local p,m
  for _,r in ipairs(pal.entities or{})do if r.player and r.player_uid==uid then p=r;break end end
  for _,r in ipairs(mc.player_vitals or{})do if r.pal_uid==uid then m=r;break end end
  if not p or not m then return {ok=false,player_uid=uid,status='verified_vitals_unavailable',pal_present=p~=nil,mc_present=m~=nil}end
  return {ok=true,player_uid=uid,server_session_id=o.session,player_health_authority='pal_server',
   pal={hp=p.hp,max_hp=p.max_hp,shield=p.shield,max_shield=p.max_shield,alive=p.alive,dying=p.dying,
    full_stomach=p.full_stomach,max_full_stomach=p.max_full_stomach,epoch=pal.epoch,revision=pal.revision,unix=pal.unix},
   mc={mc_uuid=m.mc_uuid,hearts=m.hearts,max_hearts=m.max_hearts,food=m.food,epoch=mc.epoch,revision=mc.revision,unix=mc.unix},
   expected_mc_health=p.alive and not p.dying and p.hp/p.max_hp*20 or 0}
 end
 function M.status()
  local n=0;for _ in pairs(M.views)do n=n+1 end
  return {running=M.running,phase=M.phase,authority='observer_only',native_bodies=n,mc_models=M.rendered or 0,
   pending_mc_models_and_animations=M.pending_models,damage_events_sent=0,combat_bodies_spawned=0,revision=M.revision}
 end
 function M.stop(context_alive)
  clear_views(context_alive);M.running=false;M.phase='stopped';return M.status()
 end
 return M
end
return E
