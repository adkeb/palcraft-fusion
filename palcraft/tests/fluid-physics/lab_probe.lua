-- Read-only staged Lab probe. Loading this file neither installs nor runs a feature.
-- Lead supplies {worker=<running adapter>, entity_authority=<server authority>} once.
-- Manually move the exact participant through dry/source/flow/exit/lava under a lease.
-- No teleport, item grant, damage call, movement write, RPC or service change here.
local Probe={version=1}
local allowed={dry=true,source=true,flow=true,exit=true,lava=true}
local function live(a)return a and a:IsValid()end
function Probe.new(o)
 assert(o and o.worker and o.worker.status,'Running fluid worker required')
 local sequence={};local P={}
 local function thread()local f=o.game_thread or IsInGameThread;assert(f and f()==true,'Lab fluid probe requires game thread')end
 local function capture(id)
  local status=o.worker:status();local sample
  for _,p in ipairs(status.participants or{})do if p.id==id then sample=p;break end end
  assert(sample,'Exact fluid participant is not registered')
  local state=o.worker.participants[id];assert(state and live(state.actor),'Exact participant Actor is unavailable')
  local a,m=state.actor,state.movement;assert(live(m),'Native movement unavailable')
  local r={id=id,unix=os.time(),side=status.side,phase=status.phase,world_session=status.world_session,
   dimension=status.dimension,revision=status.revision,actor=a:GetFullName(),actor_address=tostring(a:GetAddress()),
   authority=a:HasAuthority(),contact=sample,mode=m.MovementMode,gravity=m.GravityScale,
   native_swimming=m:IsSwimming(),entered_water=m:IsEnteredWater(),water_plane=m.WaterPlaneZ,in_water_rate=m:GetInWaterRate(),
   query=status.native,damage_owner=status.damage_owner,lava_damage_calls=status.lava_damage_calls,
   power_mode='night_low_power',manual_player_movement=true}
  local velocity=m:GetVelocity();r.velocity={X=velocity.X,Y=velocity.Y,Z=velocity.Z}
  local capsule=a.CapsuleComponent
  if live(capsule)then
   local half,radius=capsule:GetScaledCapsuleHalfHeight(),capsule:GetScaledCapsuleRadius()
   local center=capsule:K2_GetComponentLocation();r.native_body={radius_cm=radius,half_height_cm=half,
    component_center={X=center.X,Y=center.Y,Z=center.Z}}
   r.native_body_matches_contact=sample.shape=='capsule'and sample.bounds and sample.radius
    and math.abs(sample.radius*100-radius)<.01 and math.abs((sample.bounds[5]-sample.bounds[2])*100-half*2)<.01 or false
  end
  local controller=a:GetController()
  if live(controller)and controller:IsA('/Script/Pal.PalPlayerController')then r.player_controller_swimming=controller:IsSwimming()end
  local entity=o.entity_authority
  local e=entity and entity.native and entity.native[id]
  if e and live(e.cp)then
   local fp=StaticFindObject('/Script/Pal.Default__FixedPoint64MathLibrary');assert(live(fp),'FixedPoint utility unavailable')
   r.hp=fp:Convert_FixedPoint64ToFloat(e.cp:GetHP());r.dead=e.cp:IsDead();r.dying=e.cp:IsDying()
   r.entity_epoch=entity.epoch;r.pal_session=entity.session;r.last_entity_result=entity.last_result
  end
  return r
 end
 function P:inspect(id)thread();return capture(id)end
 function P:query_policy()
  thread();local native=assert(o.worker.native);assert(native.inspect_handles,'Native fluid handle inspection unavailable')
  local expected={};local count=0
  for _,h in ipairs(native:inspect_handles())do for _,c in ipairs(h.components)do expected[c]=true;count=count+1 end end
  local found,rows=0,{}
  for _,c in ipairs(FindAllOf('BoxComponent')or{})do if live(c)and expected[c:GetAddress()]then
   found=found+1;local responses={};local correct=true
   for channel=0,31 do
    local response=c:GetCollisionResponseToChannel(channel);responses[channel+1]=response
    if response~=((channel==14 or channel==19 or channel==25)and 2 or 0)then correct=false end
   end
   local collision,overlap=c:GetCollisionEnabled(),c:GetGenerateOverlapEvents()
   rows[#rows+1]={address=tostring(c:GetAddress()),collision=collision,overlaps=overlap,responses=responses,
    correct=correct and collision==1 and overlap==false}
  end end
  local ok=count>0 and found==count;for _,r in ipairs(rows)do if not r.correct then ok=false end end
  return{ok=ok,expected=count,found=found,components=rows,read_only=true,physics_volume_created=false,damage_volume_created=false}
 end
 function P:sample(phase,id,event_id)
  thread();assert(allowed[phase],'Expected dry/source/flow/exit/lava phase')
  if self.id then assert(id==self.id,'Fluid sequence participant changed')else self.id=id end
  local r=capture(id)
  if event_id then
   assert(type(event_id)=='string'and event_id:match('^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$'),'Exact damage event UUID required')
   assert(o.read_hit and o.read_result,'Normal entity hit/result readers required')
   r.damage_event=o.read_hit(event_id);r.last_entity_result=o.read_result(event_id)
  elseif o.read_hit and r.last_entity_result then r.damage_event=o.read_hit(r.last_entity_result.id)end
  sequence[phase]=sequence[phase]or{};sequence[phase][#sequence[phase]+1]=r;return r
 end
 function P:report()
  thread();local function last(phase)local rows=sequence[phase];return rows and rows[#rows]end
  local dry,source,flow,exit,lava=last('dry'),last('source'),last('flow'),last('exit'),last('lava')
  local result={version=1,id=self.id,sequence=sequence,power_mode='night_low_power',
   actual_swimming_verified=false,actual_flow_push_verified=false,actual_lava_damage_verified=false,
   independent_damage_periods_verified=false,items_granted=0,physics_writes=0,damage_calls=0}
  local function known(r)return r and r.contact and r.contact.observation and r.contact.observation.known==true end
  local function same(r)return r and dry and r.actor_address==dry.actor_address and r.world_session==dry.world_session and r.pal_session==dry.pal_session end
  result.actual_swimming_verified=known(dry)and known(source)and known(exit)and same(source)and same(exit)
   and dry.contact.kind=='none'and not dry.native_swimming
   and source.contact.kind=='water'and source.authority and source.native_swimming and source.entered_water
   and source.native_body_matches_contact==true
   and source.contact.surface_known==true and source.contact.observation.buoyancy_pending~=true
   and source.player_controller_swimming~=false
   and(source.contact.observation.sustained_swim_samples or 0)>=2
   and exit.contact.kind=='none'and not exit.native_swimming and not exit.entered_water and exit.gravity==dry.gravity or false
  -- A velocity difference may include input/collision. The experiment must compare
  -- passive flow movement with the input owner's simultaneous no-input recording.
  if flow then result.flow_evidence={sample=flow,no_input_recording_required=true,
   actual_force_observed=known(flow)and same(flow)and flow.authority and flow.contact.kind=='water'
    and flow.contact.observation.impulse and(flow.contact.observation.impulse.X~=0 or flow.contact.observation.impulse.Y~=0)}end
  local receipt=lava and lava.last_entity_result;local event=lava and lava.damage_event
  if receipt then result.lava_evidence={sample=lava,receipt=receipt,
   normal_pal_damage_receipt=receipt.ok==true and receipt.native_route=='SlipDamage'and event
    and event.id==receipt.id and event.target==self.id and event.environment==true and event.kind=='minecraft:lava'
    and event.session==lava.pal_session and event.target_epoch==lava.entity_epoch
    and o.entity_protocol and receipt.fingerprint==o.entity_protocol.fingerprint(event)or false,
   hp_fell=type(receipt.before_hp)=='number'and type(receipt.after_hp)=='number'and receipt.after_hp<receipt.before_hp,
   duplicate_damage_periods_require_separate_contact_window=true}end
  result.actual_lava_damage_verified=known(lava)and same(lava)and lava.authority and lava.contact.kind=='lava'
   and result.lava_evidence and result.lava_evidence.normal_pal_damage_receipt and result.lava_evidence.hp_fell or false
  result.pending={flow_passive_velocity_and_input_trace=true,native_water_channel_response_reference=true,
   lava_event_fingerprint_and_exact_target_check=not(result.lava_evidence and result.lava_evidence.normal_pal_damage_receipt),pal_environment_double_cycle_observation=true,
   mirrored_client_server_swim_correction=true}
  return result
 end
 return P
end
return Probe
