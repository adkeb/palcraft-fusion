-- Lab-only staged experiment. Lead schedules execution; this file never deploys or starts a service.
-- run{action='inspect'} is read-only. Mutation actions require explicit IDs; never select the first player/Pal.
local Probe={}
local function live(a)return a and a:IsValid()and not a:GetFullName():find('Default__',1,true)end
local function gid(g)return('%08x-%04x-%04x-%04x-%04x%08x'):format(g.A&0xffffffff,(g.B>>16)&0xffff,g.B&0xffff,(g.C>>16)&0xffff,g.C&0xffff,g.D&0xffffffff)end
function Probe.run(q)
 assert(IsInGameThread(),'Game thread required')
 local M=assert(_G.PalCraftEntityAuthority,'Entity authority not loaded')
 local status=M.status();assert(status.session and status.epoch,'Entity authority identity missing')
 local utility=StaticFindObject('/Script/Pal.Default__PalUtility');local fp=StaticFindObject('/Script/Pal.Default__FixedPoint64MathLibrary')
 local function hp(e)return fp:Convert_FixedPoint64ToFloat(e.cp:GetHP())end
 if q.action=='inspect'then
  local bodies,targets={},{}
  for id,e in pairs(M.bodies)do bodies[#bodies+1]={id=id,phase=e.phase,native_hp=e.cp and hp(e)or nil,native_name=e.actor and e.actor:GetFullName()or nil,source=e.state,render='pal_surrogate_mc_models_pending'}end
  for id,e in pairs(M.native)do targets[#targets+1]={id=id,player=e.player,hp=hp(e),max_hp=fp:Convert_FixedPoint64ToFloat(e.cp:GetMaxHP()),name=e.actor:GetFullName(),dying=e.cp:IsDying(),alive=not e.cp:IsDead()}end
  local functions={}
  for _,name in ipairs({'PalCharacterManager:SpawnNewCharacter','PalCharacterParameterComponent:OnDamage','PalCharacter:OnDeadCharacter','PalUtility:ProcessDamageAndPlayEffectsByDamageInfo','PalUtility:MakeDamageInfo'})do
   local f=StaticFindObject('/Script/Pal.'..name);functions[name]=f and f:IsValid()or false
  end
  return {ok=true,action='inspect',status=status,bodies=bodies,targets=targets,reflected_functions=functions,
   runtime_verified=status.confirmed.spawns>0 and status.confirmed.native_damage_observations>0,manual_weapon_hit_pending=true}
 elseif q.action=='pal_hit_mc_body'then
  local body=assert(M.bodies[q.mc_entity_id],'Exact registered MC entity required');assert(body.phase=='active'and live(body.actor),'Native body not active')
  local source=assert(M.native[q.pal_source_id],'Exact existing native Pal source required');assert(live(source.actor),'Pal source unavailable')
  assert(type(q.power)=='number'and q.power>=1 and q.power<=100,'Nonlethal probe power 1..100 required')
  local before=hp(body);local hooks_before=status.confirmed.native_damage_observations
  local info=utility:MakeDamageInfo{Attacker=source.actor,Defender=body.actor,Power=q.power,Category=0,Element=1,AttackType=1,
   HitLocation=body.actor:K2_GetActorLocation(),DamageRatePerCollision=1,SneakAttackRate=1,PvPBuildingDamageRate=1,
   PvPPlayerToGuildPalDamageRate=1,CollectionObjectDamageRate=1,WeaponDamageRatePvP=1,bAttackableToFriend=false,IgnoreShield=false,bCannotKill=false}
  utility:ProcessDamageAndPlayEffectsByDamageInfo(source.actor,body.actor,info,true,0)
  local after=hp(body);local observed=M.confirmed.native_damage_observations>hooks_before
  return {ok=observed and before==after,action=q.action,native_guard_hp_before=before,native_guard_hp_after=after,
   native_hook_observed=observed,mc_damage_receipt='Read entities/mc-result-*.json after the next MC ticks',
   status=observed and'await_mc_receipt'or'pending_native_hook_confirmation',player_hp_untouched=true,
   test_origin='explicit_native_api_probe_not_manual_weapon_input',drops_generated_here=0}
 elseif q.action=='mc_hit_pal'then
  local body=assert(M.bodies[q.mc_entity_id],'Exact registered MC attacker required');assert(body.phase=='active','MC body not active')
  local target=assert(M.native[q.pal_target_id],'Exact existing native Pal target required');assert(not target.player,'Never damage the 1HP test player via this probe')
  local save=target.ip:GetSaveParameter();assert(gid(save.OwnerPlayerUId)=='00000000-0000-0000-0000-000000000000','Never damage an owned Pal in this probe')
  assert(type(q.amount)=='number'and q.amount>0 and q.amount<=20,'Probe damage 0..20 required')
  assert(q.allow_death==true,'Lead must explicitly schedule possible death/drop observation')
  local id=gid(StaticFindObject('/Script/Engine.Default__KismetGuidLibrary'):NewGuid())
  local hit={v=1,t='entity_damage',authority='mc_server',session=M.session,id=id,source_epoch=M.protocol.source_epoch,
   target_epoch=M.epoch,source=body.id,target=q.pal_target_id,amount=q.amount,kind='minecraft:mob_attack'}
  local first=M.protocol.hit(hit);local replay=M.protocol.hit(hit)
  return {ok=first.ok==true and first.accepted==true,action=q.action,event_id=id,first=first,replay=replay,drop_owner='palworld',
   test_origin='lab_protocol_fixture_not_manual_mc_attack',manual_game_hit_pending=true,items_granted_to_player=0}
 elseif q.action=='cleanup'then return M.stop()
 else error('Unknown Lab probe action')end
end
return Probe
