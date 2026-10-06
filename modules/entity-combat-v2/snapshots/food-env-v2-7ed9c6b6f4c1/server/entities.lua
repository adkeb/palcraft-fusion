-- Pal server authority for real actor hit bodies and native combat. Load once and tick on the game thread.
local dir=assert(debug.getinfo(1,'S').source:match('^@(.*[/\\])'))
local P=dofile(dir..'entity_protocol.lua')
local E={}
local ZERO={A=0,B=0,C=0,D=0}
local function live(a)return a and a:IsValid()and not a:GetFullName():find('Default__',1,true)end
local function str(v)return type(v)=='string'and v or v:ToString()end
local function guid(g)return('%08x-%04x-%04x-%04x-%04x%08x'):format(g.A&0xffffffff,(g.B>>16)&0xffff,g.B&0xffff,(g.C>>16)&0xffff,g.C&0xffff,g.D&0xffffffff)end
local function plain_guid(g)return {A=g.A,B=g.B,C=g.C,D=g.D}end
local function unwrap(v)return v and v.get and v:get()or v end
local DEFAULT_SPECIES={['minecraft:sheep']='SheepBall',['minecraft:cow']='CowPal',['minecraft:chicken']='ChickenPal',
 ['minecraft:pig']='BoarPal',['minecraft:wolf']='Garm',['minecraft:cat']='PinkCat',['minecraft:rabbit']='CuteFox',
 ['minecraft:zombie']='DreamDemon',['minecraft:husk']='DreamDemon',['minecraft:drowned']='DreamDemon',
 ['minecraft:skeleton']='DarkCrow',['minecraft:stray']='DarkCrow',['minecraft:creeper']='GhostBeast',
 ['minecraft:spider']='Garm',['minecraft:cave_spider']='Garm',['minecraft:slime']='NegativeKoala',
 ['minecraft:phantom']='NightFox',['minecraft:bat']='DarkCrow',['minecraft:blaze']='FlameBambi',
 ['minecraft:enderman']='DarkScorpion',['minecraft:villager']='SheepBall'}

function E.new(o)
 o=o or{};assert(IsInGameThread(),'Entities must be initialized on the game thread')
 local root=assert(o.root,'Entity transport directory required'):gsub('\\','/'):gsub('/?$','/')
 local J=assert(o.json,'JSON adapter required');local now=o.now or os.time
 local O=assert(o.origin,'World origin required');local active_dimension=o.dimension or'minecraft:overworld'
 local scale=o.pal_damage_per_mc_health or 50;assert(P.finite(scale)and scale>0,'Damage conversion required')
 local function read(name)
  if o.read then return o.read(name)end
  local path=(name:match('^%a:[/\\]')or name:sub(1,1)=='/')and name or root..name
  local f=io.open(path,'rb');if not f then return end
  local size=f:seek('end');assert(size<=1048576,'Entity message too large');f:seek('set');local raw=f:read('*a');f:close();return J.decode(raw)
 end
 local function write(name,v)
  if o.write then return o.write(name,v)end
  local f=assert(io.open(root..name..'.tmp','wb'));assert(f:write(J.encode(v)));f:close();os.remove(root..name);assert(os.rename(root..name..'.tmp',root..name))
 end
 local utility=StaticFindObject('/Script/Pal.Default__PalUtility')
 local fp=StaticFindObject('/Script/Pal.Default__FixedPoint64MathLibrary')
 local ids=StaticFindObject('/Script/Engine.Default__KismetGuidLibrary')
 assert(utility and utility:IsValid()and fp and fp:IsValid()and ids and ids:IsValid(),'Native utilities unavailable')
 local gs
 for _,a in ipairs(FindAllOf('PalGameStateInGame')or{})do if live(a)and a:HasAuthority()then gs=a;break end end
 assert(gs,'Authoritative Pal game state required; client observer cannot run server entities')
 local session=str(gs.ServerSessionId);assert(not o.session or o.session==session,'Pal session mismatch')
 local epoch=guid(ids:NewGuid());local manager=utility:GetCharacterManager(gs);assert(live(manager),'Character manager unavailable')
 local database
 for _,a in ipairs(FindAllOf('PalDatabaseCharacterParameter')or{})do if live(a)then database=a;break end end
 assert(live(database),'Character database unavailable')
 local M={running=true,session=session,epoch=epoch,revision=0,ticks=0,bodies={},native={},by_actor={},by_parameter={},
  hooks={},errors={},confirmed={spawns=0,native_damage_observations=0,pal_damage=0,deaths=0},unprojected={},phase='waiting_for_mc_server'}
 local function numeric(v)return type(v)=='number'and v or fp:Convert_FixedPoint64ToFloat(v)end
 local function parameter(a)local cp=a:GetCharacterParameterComponent();assert(live(cp),'Character component unavailable');local ip=cp:GetIndividualParameter();assert(live(ip),'Individual parameter unavailable');return cp,ip end
 local function id_for(a)
  local cp,ip=parameter(a);local h=manager:GetIndividualHandleFromCharacterParameter(ip);assert(live(h),'Individual handle unavailable')
  local id=h:GetIndividualID();return 'pal:'..guid(id.PlayerUId)..'/'..guid(id.InstanceId),cp,ip,h
 end
 local function world(r)return {X=O.X+r.x*100,Y=O.Y-r.z*100,Z=O.Z+(r.y-64)*100}end
 local function mc(p)return (p.X-O.X)/100,64+(p.Z-O.Z)/100,-(p.Y-O.Y)/100 end
 local function remove(e)
  if e.actor and live(e.actor)then M.by_actor[e.actor:GetAddress()]=nil end
  if e.cp and live(e.cp)then M.by_parameter[e.cp:GetAddress()]=nil end
  if live(e.handle)then manager:DespawnCharacterByHandle(e.handle,nil)end
 end
 local function configure(e)
  local a=e.handle:TryGetIndividualActor();if not live(a)then return false end
  assert(a:HasAuthority(),'Spawned body lacks server authority')
  if not a:IsInitialized()then return false end
  local cp,ip=parameter(a);if numeric(cp:GetMaxHP())<=0 then return false end
  local controller=a:GetController()
  if live(controller)then assert(controller:IsA('/Script/Pal.PalAIController'),'Body controller is not a Pal AI controller');controller:SetActiveAI(false)end
  a.CharacterMovement:DisableMovement()
  ip:SetUncapturable(true);ip:SetDisableNaturalHealing(true);ip:SetDisableNaturalUpdate(true)
  ip:SetCanTargetFromAI(true)
  e.actor,e.cp,e.ip=a,cp,ip;e.native_id=id_for(a);M.by_actor[a:GetAddress()]=e;M.by_parameter[cp:GetAddress()]=e
  if not e.guard_registered then e.original_hp=numeric(cp:GetHP());e.guard_registered=true end
  a:SetActiveActor(true);controller=a:GetController()
  if not live(controller)then e.phase='awaiting_native_controller';return false end
  assert(controller:IsA('/Script/Pal.PalAIController'),'Body controller is not a Pal AI controller')
  controller:SetActiveAI(false);a.CharacterMovement:DisableMovement()
  if e.phase~='active'then M.confirmed.spawns=M.confirmed.spawns+1 end;e.phase='active'
  return true
 end
 local function spawn(r)
  assert(M.hooks.damage,'Native damage hook must exist before a body can be spawned')
  local data={};local species=(o.species or DEFAULT_SPECIES)[r.kind]or'SheepBall'
  local setup=database:SetupSaveParameter(FName(species),o.body_level or 1,ZERO,data)
  assert(setup,'Native database rejected surrogate species '..species)
  local save=data.outParameter or data;assert(save.CharacterID,'Save parameter output unavailable')
  save.NickName='MC '..r.kind;save.FilteredNickName=save.NickName;save.IsPlayer=false
  local loc=world(r);loc.Z=loc.Z+r.height*50
  local name='PalCraftMC_'..r.id:sub(4):gsub('%-','')
  local handle=manager:SpawnNewCharacter(save,{Name=FName(name),Owner=gs,SpawnLocation=loc,
   SpawnRotation={Pitch=0,Yaw=-90-r.yaw,Roll=0},SpawnScale={X=1,Y=1,Z=1},SpawnCollisionHandlingOverride=2,
   bAlwaysRelevant=false,bNeedAdjustToFloor=false,bStartAsInactivePalCharacter=true},nil)
  assert(live(handle),'SpawnNewCharacter did not return an IndividualHandle')
  local e={id=r.id,state=r,handle=handle,phase='awaiting_native_actor',species=species,requested=now(),name=name}
  M.bodies[r.id]=e;configure(e);return e
 end
 local function update_body(e,r)
  e.state=r;e.missing=0
  if not e.actor or not live(e.actor)or e.phase~='active'then
   if not configure(e)then assert(now()-e.requested<10,'Native actor spawn timed out');return end
  end
  local p=world(r);local half=e.actor.CapsuleComponent:GetScaledCapsuleHalfHeight();p.Z=p.Z+half
  e.actor:K2_SetActorLocation(p,false,{},true);e.actor:K2_SetActorRotation({Pitch=0,Yaw=-90-r.yaw,Roll=0},false)
  e.actor:SetActorEnableCollision(r.alive==true);e.ip:SetCanTargetFromAI(r.alive==true)
  e.actor:ForceNetUpdate()
  -- HP is never written to a real Pal. Native bodies retain their spawn HP and cannot produce native death loot.
  if numeric(e.cp:GetHP())~=e.original_hp then
   M.errors[e.id]='surrogate_native_hp_changed';M.phase='native_damage_guard_failed';M.running=false
   error('Native damage guard failed for '..e.id)
  end
 end
 local function authenticated_player(mc_uuid,proof)
  local table=read(o.sessions_file or'../auth/authenticated-sessions.json');if not table then return nil,'missing_authenticated_sessions'end
  local age=now()-(table.updated_unix or 0)
  if table.v~=2 or age< -5 or age>5 or table.server_session_id~=session then return nil,'stale_authenticated_sessions'end
  local world_id=o.world_id or str(gs:GetWorldSaveDirectoryName())
  if table.world_id~=world_id then return nil,'world_identity_mismatch'end
  for _,r in ipairs(table.sessions or{})do
   if r.mc_uuid==mc_uuid and not r.legacy and P.uuid(r.pal_uid)and (r.expires_at or 0)>now()then
    if not proof or proof.mc_uuid~=r.mc_uuid or proof.pal_uid~=r.pal_uid or proof.world_id~=table.world_id
      or proof.server_session_id~=session or proof.session_id~=r.session_id or proof.generation~=r.generation then return nil,'source_connection_generation_mismatch'end
    for _,pc in ipairs(FindAllOf('PalPlayerController')or{})do
     if live(pc)and pc:HasAuthority()and guid(pc:GetPlayerUId())==r.pal_uid and live(pc.Pawn)then return pc.Pawn,r end
    end
   end
  end
  return nil,'unbound_or_offline_source_player'
 end
 local function environmental_proxy(q,target)
  assert(not target.player and q.source_proxy==true,'Native non-player proxy environment required')
  assert(q.kind=='minecraft:lava'or q.kind=='minecraft:in_fire'or q.kind=='minecraft:on_fire','Non-player environment currently supports actual fire/lava; aquatic drowning is native')
  local state=read('mc-state.json');assert(state and state.session==session and state.epoch==M.protocol.source_epoch and now()-state.unix>=-5 and now()-state.unix<=3,'Fresh MC proxy authority required')
  local pos=target.actor:K2_GetActorLocation();local half=target.actor.CapsuleComponent:GetScaledCapsuleHalfHeight()
  local x,y,z=mc{X=pos.X,Y=pos.Y,Z=pos.Z-half}
  for _,r in ipairs(state.host_proxies or{})do
   if r.id==q.source and r.pal_id==q.target and r.dimension==active_dimension then
    assert((r.x-x)^2+(r.y-y)^2+(r.z-z)^2<=25,'Native target moved out of MC contact proxy bounds')
    if o.environment_contact then assert(o.environment_contact(q,target)==true,'Native exact committed fluid contact not proven')end
    return true
   end
  end
  error('MC environment source is not the target native Pal proxy')
 end
 local function apply(q)
  assert(IsInGameThread(),'Native combat requires game thread')
  local target=M.native[q.target];assert(target and live(target.actor),'Real Pal target unavailable')
  local cp=target.cp;assert(not cp:IsDead(),'Target already dead')
  local attacker,binding
  if q.source_player then attacker,binding=authenticated_player(q.source:sub(4),q.player_session);assert(attacker,'Verified player unavailable: '..tostring(binding))
  elseif not q.environment then local body=M.bodies[q.source];assert(body and body.phase=='active'and live(body.actor),'MC attacker body unavailable');attacker=body.actor end
  local before,shield_before=numeric(cp:GetHP()),numeric(target.ip:GetShieldHP())
  local alive_before,dying_before=not cp:IsDead(),cp:IsDying()
  local power=math.max(1,math.floor(q.amount*scale+.5))
  if q.environment then
   if target.player then
    local bound=authenticated_player(q.source:sub(4),q.player_session);assert(bound and bound:GetAddress()==target.actor:GetAddress(),'Environmental damage player mismatch')
   else environmental_proxy(q,target)end
   local dead={['minecraft:fall']=4,['minecraft:drown']=7,['minecraft:on_fire']=6,['minecraft:in_fire']=6,['minecraft:lava']=6,['minecraft:starve']=0,['minecraft:poison']=5}
   local kind=dead[q.kind];assert(kind~=nil,'Environmental damage kind pending native mapping: '..q.kind)
   target.actor.DamageReactionComponent:SlipDamage(power,true,kind,false)
  else
   local _,ip=parameter(attacker)
   local make={Attacker=attacker,Defender=target.actor,Power=power,Category=0,Element=1,AttackType=q.source_player and 1 or 0,WeaponType=0,
    HitLocation=target.actor:K2_GetActorLocation(),IsLeanBack=false,IsBlow=false,SneakAttackRate=1,DamageRatePerCollision=1,
    PvPBuildingDamageRate=1,PvPPlayerToGuildPalDamageRate=1,CollectionObjectDamageRate=1,WeaponDamageRatePvP=1,
    bAttackableToFriend=false,NoDamage=false,IgnoreShield=false,IgnorePlayerEquipItemDamage=false,bCannotKill=false,
    bIsExplosionDamage=q.kind:find('explosion',1,true)~=nil}
   local info=utility:MakeDamageInfo(make)
   -- The native calculator, friendly-fire checks, shield/armor, AI retaliation and death pipeline remain enabled.
   info.AttackerGroupID=plain_guid(ip:GetGroupId())
   utility:ProcessDamageAndPlayEffectsByDamageInfo(attacker,target.actor,info,true,0)
  end
  local after,shield_after=numeric(cp:GetHP()),numeric(target.ip:GetShieldHP())
  local observed=M.last_native_damage and M.last_native_damage.defender==q.target and M.last_native_damage.serial>M.current_apply_serial
  local changed=after~=before or shield_after~=shield_before or alive_before~=not cp:IsDead()or dying_before~=cp:IsDying()
  if changed then M.confirmed.pal_damage=M.confirmed.pal_damage+1 end
  return {ok=changed or observed,accepted=changed,native_damage_observed=observed==true,
   status=changed and'applied'or observed and'blocked_by_native_rules'or'pending_native_confirmation',
   before_hp=before,after_hp=after,before_shield=shield_before,after_shield=shield_after,alive=not cp:IsDead(),dying=cp:IsDying(),
   before_alive=alive_before,before_dying=dying_before,
   native_route=q.environment and'SlipDamage'or'ProcessDamageAndPlayEffectsByDamageInfo',player_attributed=binding~=nil,drop_owner='palworld'}
 end
 local protocol=P.new{session=session,epoch=epoch,read=read,write=write,now=now,apply=function(q)
  M.current_apply_serial=M.damage_serial or 0;M.applying_damage=q
  local ok,result=pcall(apply,q);M.applying_damage=nil
  if not ok then error(result)end;return result
 end}
 M.protocol=protocol
 local food_native,food_protocol,food_error
 if o.food_enabled~=false then
  local good,worker=pcall(function()return dofile(dir..'food_native.lua').new{game_state=gs,epoch=epoch,fixed=fp,now=now}end)
  if good then
   food_native=worker
   food_protocol=dofile(dir..'food_protocol.lua').new{protocol=P,session=session,epoch=epoch,source_epoch=function()return protocol.source_epoch end,
    read=read,write=write,apply=function(q)
     local target=assert(M.native[q.target],'Food target not in native authority snapshot')
     local a,b=authenticated_player(q.source:sub(4),q.player_session)
     assert(a and target.player and a:GetAddress()==target.actor:GetAddress(),'Food consumer identity mismatch')
     return food_native.apply(q,target)
    end}
  else food_error=tostring(worker)end
 end
 local function native_damage(context,damage_param)
  local cp=unwrap(context);if not live(cp)then return end
  local owner=cp:GetOwner();if not live(owner)or not owner:HasAuthority()then return end
  local result=unwrap(damage_param);local body=M.by_parameter[cp:GetAddress()]
  M.damage_serial=(M.damage_serial or 0)+1
  local attacker_body=live(result.Attacker)and M.by_actor[result.Attacker:GetAddress()]
  if not body and attacker_body then
   local expected=M.applying_damage;local target_id=id_for(owner)
   if not expected or expected.source~=attacker_body.id or expected.target~=target_id then
    result.Damage=0;result.ActualDamage=0;result.bCannotKill=true
    M.suppressed_surrogate_attacks=(M.suppressed_surrogate_attacks or 0)+1;return
   end
  end
  if body then
   local amount=result.Damage
   -- Only this server HP-stage hook forwards damage. Client FX and subsequent damage/death hooks never do.
   if P.finite(amount)and amount>0 and M.running and protocol.source_epoch then
    local attacker=result.Attacker
    if live(attacker)and not M.by_actor[attacker:GetAddress()]then
     local from=id_for(attacker);local id=guid(ids:NewGuid())
     local q={v=1,t='entity_damage',authority='pal_server',session=session,id=id,source_epoch=epoch,
      target_epoch=protocol.source_epoch,target=body.id,source=from,amount=amount/scale,kind='pal:native',unix=now()}
     assert(P.finite(q.amount)and q.amount<=10000,'Native damage conversion limit')
     write('pal-hit-'..id..'.json',q);M.confirmed.native_damage_observations=M.confirmed.native_damage_observations+1
    end
   end
   -- Surrogate native HP/death is disabled at the normal HP stage; MC owns the only death and loot.
   result.Damage=0;result.ActualDamage=0;result.bCannotKill=true
  else
   local defender=id_for(owner)
   M.last_native_damage={defender=defender,serial=M.damage_serial,amount=result.Damage}
  end
 end
 local function hook(path,pre,post)
  local fn=StaticFindObject(path);assert(live(fn),'Missing native function '..path)
  local a,b=RegisterHook(path,pre,post);assert(a and b,'Native hook registration did not return both IDs')
  return {path=path,pre=a,post=b}
 end
 M.hooks.damage=hook('/Script/Pal.PalCharacterParameterComponent:OnDamage',function(c,d)
  local ok,why=pcall(native_damage,c,d)
  if not ok then M.phase='native_hook_error';M.errors.damage=tostring(why);M.running=false
   -- If transport fails, still prevent a native surrogate kill/reward. Never silently revert to two authorities.
   local cp=unwrap(c);local body=live(cp)and M.by_parameter[cp:GetAddress()]
   if body then local result=unwrap(d);result.Damage=0;result.ActualDamage=0;result.bCannotKill=true end
  end
 end)
 M.hooks.death=hook('/Script/Pal.PalCharacter:OnDeadCharacter',function()end,function(c,d)
  local a=unwrap(c);if not live(a)or not a:HasAuthority()then return end
  if M.by_actor[a:GetAddress()]then M.phase='unexpected_surrogate_death';M.errors.death='Native death guard failed';M.running=false;return end
  local ok,id=pcall(id_for,a);if not ok then M.errors.death=tostring(id);return end
  if not M.dead_seen then M.dead_seen={}end
  if not M.dead_seen[id]then M.dead_seen[id]=true;M.confirmed.deaths=M.confirmed.deaths+1
   write('pal-death-'..guid(ids:NewGuid())..'.json',{v=1,t='entity_death',authority='pal_server',session=session,epoch=epoch,entity=id,drop_owner='palworld',unix=now()})
  end
 end)
 local function scan()
  local rows=J.array();M.native={}
  local centers={}
  for _,pc in ipairs(FindAllOf('PalPlayerController')or{})do if live(pc)and pc:HasAuthority()and live(pc.Pawn)then centers[#centers+1]=pc.Pawn:K2_GetActorLocation()end end
  for _,a in ipairs(FindAllOf('PalCharacter')or{})do
   if live(a)and a:HasAuthority()and not M.by_actor[a:GetAddress()]then
    local pos=a:K2_GetActorLocation();local near=false
    for _,c in ipairs(centers)do if (pos.X-c.X)^2+(pos.Y-c.Y)^2+(pos.Z-c.Z)^2<=9600^2 then near=true;break end end
    if near then
     local ok,id,cp,ip,h=pcall(id_for,a)
     if ok then
      local individual=h:GetIndividualID();local capsule=a.CapsuleComponent
      local half=live(capsule)and capsule:GetScaledCapsuleHalfHeight()or 90
      local radius=live(capsule)and capsule:GetScaledCapsuleRadius()or 30
      local x,y,z=mc{X=pos.X,Y=pos.Y,Z=pos.Z-half}
      local player=a:IsA('/Script/Pal.PalPlayerCharacter')
      local row={id=id,kind=str(ip:GetCharacterID()),x=x,y=y,z=z,yaw=-90-a:K2_GetActorRotation().Yaw,
       hp=numeric(cp:GetHP()),max_hp=numeric(cp:GetMaxHP()),shield=numeric(ip:GetShieldHP()),max_shield=numeric(ip:GetShieldMaxHP()),
       width=radius*2/100,height=half*2/100,alive=not cp:IsDead(),dying=cp:IsDying(),player=player,
       full_stomach=cp:GetFullStomach(),max_full_stomach=cp:GetMaxFullStomach(),
       player_uid=guid(individual.PlayerUId),group=guid(ip:GetGroupId()),dimension=active_dimension}
      local controller=a:GetController()
      if live(controller)and not player and controller:IsA('/Script/Pal.PalAIController')then
       local hate=controller:GetHateSystem();if live(hate)then local target=hate:FindMostHateTarget();if live(target)then local b=M.by_actor[target:GetAddress()];row.target=b and b.id or nil end end
      end
      rows[#rows+1]=row;M.native[id]={actor=a,cp=cp,ip=ip,handle=h,player=player}
      if #rows>=512 then break end
     else M.errors[a:GetFullName()]=tostring(id)end
    end
   end
  end
  local food={v=1,enabled=food_native~=nil,ready_players=J.array(),confirmed_native_effects=food_native and food_native.confirmed or 0,error=food_error}
  if food_native then
   if M.food_cap_unix~=now()then
    M.food_cap_unix=now();M.food_ready={}
    for id,e in pairs(M.native)do e.id=id;if e.player and not e.cp:IsDead()and not e.cp:IsDying()and food_native.readiness(e)then M.food_ready[id]=true end end
   end
   for id in pairs(M.food_ready or{})do food.ready_players[#food.ready_players+1]=id end
  end
  local bodies=J.array()
  for id,e in pairs(M.bodies)do if e.native_id and e.phase=='active'and live(e.actor)then
   bodies[#bodies+1]={id=id,native_id=e.native_id,kind=e.state.kind,dimension=e.state.dimension,phase=e.phase,source_epoch=protocol.source_epoch,body_epoch=epoch,actor_name=e.actor:GetFullName()}
  end end
  M.revision=M.revision+1;write('pal-state.json',{v=1,t='entity_snapshot',authority='pal_server',session=session,epoch=epoch,revision=M.revision,unix=now(),entities=rows,food=food,bodies=bodies})
 end
 function M.tick()
  assert(IsInGameThread(),'Entity tick must run on game thread');if not M.running then return M.status()end
  local ok,why=pcall(function()
   assert(live(gs)and str(gs.ServerSessionId)==session,'Pal world changed')
   M.ticks=M.ticks+1;if food_native then food_native.tick()end;scan()
   local q=read('mc-state.json')
   if q and q.session==session and P.finite(q.unix)and now()-q.unix<=3 and now()-q.unix>=-5 then
    local changed,new_epoch=protocol.snapshot(q)
    if changed then
     if new_epoch then for _,e in pairs(M.bodies)do remove(e)end;M.bodies={}end
     M.mc_seen=now();M.phase='active';local wanted={};M.unprojected={}
     local spawned=0
     for _,r in ipairs(q.entities)do
      if r.category=='mob'and(r.alive or(r.death_time or 0)>0 and(r.death_time or 0)<=20)and r.dimension==active_dimension then
       wanted[r.id]=true;local e=M.bodies[r.id]
       if not e and spawned<4 then e=spawn(r);spawned=spawned+1 end
       if e then update_body(e,r)end
      elseif r.category=='mob'and r.dimension~=active_dimension then M.unprojected[r.id]=r.dimension end
     end
     for id,e in pairs(M.bodies)do if not wanted[id]then e.missing=(e.missing or 0)+1;if e.missing>2 then remove(e);M.bodies[id]=nil end end end
    end
   end
   if M.mc_seen and now()-M.mc_seen>3 then for _,e in pairs(M.bodies)do remove(e)end;M.bodies={};M.phase='mc_server_stale'end
   -- Reliable journal: scan the IDs from the authority index, not a filesystem shell or client payload.
   local index=read('mc-hits.json')
   if index and index.session==session and index.epoch==protocol.source_epoch then
    for i,id in ipairs(index.ids or{})do if i>32 then break end
     if P.uuid(id)then local hit=read('mc-hit-'..id..'.json');if hit then assert(hit.id==id,'Hit index/file identity mismatch');local result=protocol.hit(hit);M.last_result=result end end
    end
   end
   local meals=read('mc-foods.json')
   if food_protocol and meals and meals.session==session and meals.epoch==protocol.source_epoch then
    for i,id in ipairs(meals.ids or{})do if i>8 then break end
     if P.uuid(id)then local q=read('mc-food-'..id..'.json');if q then assert(q.id==id,'Food index/file mismatch');M.last_food_result=food_protocol.consume(q)end end
    end
   end
  end)
  if not ok then M.phase='runtime_error';M.errors.tick=tostring(why);M.running=false end
  write('pal-status.json',M.status());return M.status()
 end
 function M.status()
  local n=0;local bodies=J.array();for id,e in pairs(M.bodies)do n=n+1;bodies[#bodies+1]={id=id,phase=e.phase,species=e.species,actor_name=e.actor and live(e.actor)and e.actor:GetFullName()or nil,render='native_pal_surrogate_pending_mc_model'}end
  return {v=1,t='entity_status',authority='pal_server',running=M.running,phase=M.phase,session=session,epoch=epoch,
   bodies=n,mappings=bodies,errors=M.errors,confirmed=M.confirmed,pending={mc_models_and_animations=true,native_spawn_and_hooks=M.confirmed.spawns==0,native_despawn_confirmation=M.cleanup_pending or 0},
   unprojected=M.unprojected,applied=protocol.applied,rejected=protocol.rejected,uncertain=protocol.uncertain,suppressed_surrogate_attacks=M.suppressed_surrogate_attacks or 0,
   player_health_authority='pal_server',food_authority='pal_server',mc_food_use=food_native and'paid_vanilla_to_native_processor'or'pending_native_food_classes',
   food=food_native and food_native.status()or{error=food_error},food_ledger=food_protocol and{applied=food_protocol.applied,pending=food_protocol.pending,rejected=food_protocol.rejected}or nil,
   nonplayer_environment='original_mc_proxy_lava_fire_to_single_native_SlipDamage'}
 end
 function M.stop()
  assert(IsInGameThread(),'Entity stop must run on game thread');M.running=false
  if food_native then food_native.stop()end
  M.cleanup_pending=0
  for _,e in pairs(M.bodies)do remove(e);if live(e.handle)and live(e.handle:TryGetIndividualActor())then M.cleanup_pending=M.cleanup_pending+1 end end;M.bodies={}
  for _,h in pairs(M.hooks)do UnregisterHook(h.path,h.pre,h.post)end;M.hooks={};M.phase=M.cleanup_pending>0 and'stop_requested_pending_native_despawn'or'stopped'
  write('pal-status.json',M.status());return M.status()
 end
 return M
end
return E
