-- Models the reflected SDK boundary; this does not pretend to prove an actual UE native call or hook.
local root=assert(arg[1]);local J=dofile(assert(arg[2]));local cases={};local passed=0
local function clone(x)return J.decode(J.encode(x))end
local function test(name,f)local ok,why=pcall(f);assert(ok,name..': '..tostring(why));passed=passed+1;cases[#cases+1]=name end
local ADDR=100;local function obj(name,methods)
 ADDR=ADDR+1;local a=methods or{};a.addr=ADDR;a.name=name;a.valid=true
 a.IsValid=function(s)return s.valid end;a.GetFullName=function(s)return s.name end;a.GetAddress=function(s)return s.addr end
 return a
end
local function wrap(x)return {get=function()return x end}end
local function g(n)return {A=n,B=0,C=0,D=n}end
local function gid(n)return ('%08x-0000-0000-0000-%012x'):format(n,n)end
local UID=gid(1);local PID='pal:'..UID..'/'..gid(2);local MOB='mc:'..gid(3)
local function setup()
 local store={};local clock=100;local hooks={};local counts={spawn=0,despawn=0,damage=0,drops=0,unhook=0,slip=0,ai=0}
 local all={};local handles={};local serial=10;local hook_serial=0
 IsInGameThread=function()return true end
 FName=function(s)return {ToString=function()return s end}end
 local function actor(name,uid,instance,player)
  local a=obj(name,{HasAuthority=function()return true end,IsA=function(_,c)return c=='/Script/Pal.PalPlayerCharacter'and player or c=='/Script/Pal.PalCharacter'end})
  a.pos={X=0,Y=0,Z=90};a.rotation={Pitch=0,Yaw=0,Roll=0}
  a.K2_GetActorLocation=function(s)return s.pos end;a.K2_GetActorRotation=function(s)return s.rotation end
  a.K2_SetActorLocation=function(s,p,sweep,hit,teleport)assert(not sweep and teleport);s.pos=p;return true end
  a.K2_SetActorRotation=function(s,r)s.rotation=r end;a.ForceNetUpdate=function()end;a.SetActiveActor=function()end;a.SetActorEnableCollision=function()end
  a.CharacterMovement=obj('movement',{DisableMovement=function()end})
  a.CapsuleComponent=obj('capsule',{GetScaledCapsuleHalfHeight=function()return 90 end,GetScaledCapsuleRadius=function()return 30 end})
  local ip=obj('individual',{GetCharacterID=function()return FName(player and'Player'or'SheepBall')end,GetGroupId=function()return g(0)end,
   GetShieldHP=function()return 0 end,GetShieldMaxHP=function()return 0 end,SetUncapturable=function(_,v)assert(v)end,
   SetDisableNaturalHealing=function(_,v)assert(v)end,SetDisableNaturalUpdate=function(_,v)assert(v)end,SetCanTargetFromAI=function(_,v)assert(v)end})
  local cp=obj('component',{hp=1000,GetOwner=function()return a end,GetIndividualParameter=function()return ip end,
   GetHP=function(s)return {Value=s.hp}end,GetMaxHP=function()return {Value=1000}end,GetFullStomach=function()return 10 end,GetMaxFullStomach=function()return 100 end,
   IsDead=function(s)return s.hp<=0 end,IsDying=function()return false end})
  a.GetCharacterParameterComponent=function()return cp end;a.IsInitialized=function()return true end
  local hate=obj('hate',{FindMostHateTarget=function()end})
  local controller=obj('AIController',{IsA=function(_,c)return c=='/Script/Pal.PalAIController'end,
   SetActiveAI=function(_,v)assert(not v);counts.ai=counts.ai+1 end,GetHateSystem=function()return hate end})
  a.GetController=function()return controller end
  local handle=obj('handle',{GetIndividualID=function()return {PlayerUId=g(uid),InstanceId=g(instance)}end,TryGetIndividualActor=function()return a end})
  handles[ip]=handle;all[#all+1]=a
  return a,cp,ip,handle
 end
 local player,player_cp=actor('RealPlayer',1,2,true)
 local target,target_cp=actor('RealWildPal',0,4,false)
 local pc=obj('PlayerController',{HasAuthority=function()return true end,Pawn=player,GetPlayerUId=function()return g(1)end})
 local gs=obj('GameState',{HasAuthority=function()return true end,ServerSessionId='lab-session',GetWorldSaveDirectoryName=function()return 'world-lab'end})
 local function damage(attacker,defender,power)
  local cp=defender:GetCharacterParameterComponent();local info={Attacker=attacker,Defender=defender,Damage=power,ActualDamage=power,bCannotKill=false}
  local h=hooks['/Script/Pal.PalCharacterParameterComponent:OnDamage'];if h and h.pre then h.pre(wrap(cp),wrap(info))end
  cp.hp=math.max(0,cp.hp-info.Damage)
  if cp.hp==0 then counts.drops=counts.drops+1;local d=hooks['/Script/Pal.PalCharacter:OnDeadCharacter'];if d and d.post then d.post(wrap(defender),wrap({}))end end
  return info
 end
 player.DamageReactionComponent=obj('reaction',{SlipDamage=function(_,power,ignore,kind,clear)assert(ignore and not clear);counts.slip=counts.slip+1;damage(player,player,power)end})
 local manager=obj('Manager',{GetIndividualHandleFromCharacterParameter=function(_,ip)return handles[ip]end,
  SpawnNewCharacter=function(_,save,spawn,delegate)
   assert(delegate==nil,'Unbound delegate required');assert(spawn.bStartAsInactivePalCharacter,'Register HP guard before activation')
   counts.spawn=counts.spawn+1;local a,cp,ip,h=actor(spawn.Name:ToString(),0,100+counts.spawn,false);a.pos=spawn.SpawnLocation
   return h
  end,DespawnCharacterByHandle=function(_,h,delegate)assert(delegate==nil);counts.despawn=counts.despawn+1;h:TryGetIndividualActor().valid=false end})
 local util=obj('Default__PalUtility',{GetCharacterManager=function()return manager end,MakeDamageInfo=function(_,q)return clone{Power=q.Power}end,
  ProcessDamageAndPlayEffectsByDamageInfo=function(_,a,d,info,fx,exceed)assert(fx and exceed==0);counts.damage=counts.damage+1;damage(a,d,info.Power)end})
 local fp=obj('Default__FixedPoint64MathLibrary',{Convert_FixedPoint64ToFloat=function(_,v)return v.Value end})
 local ids=obj('Default__KismetGuidLibrary',{NewGuid=function()serial=serial+1;return g(serial)end})
 local db=obj('Database',{SetupSaveParameter=function(_,name,level,owner,out)assert(level==1 and owner.A==0);out.CharacterID=name;return true end})
 StaticFindObject=function(path)
  if path=='/Script/Pal.Default__PalUtility'then return util elseif path=='/Script/Pal.Default__FixedPoint64MathLibrary'then return fp
  elseif path=='/Script/Engine.Default__KismetGuidLibrary'then return ids else return obj('Function '..path)end
 end
 FindAllOf=function(c)if c=='PalGameStateInGame'then return {gs}elseif c=='PalDatabaseCharacterParameter'then return {db}elseif c=='PalPlayerController'then return {pc}elseif c=='PalCharacter'then return all end;return {}end
 RegisterHook=function(path,pre,post)hook_serial=hook_serial+2;hooks[path]={pre=pre,post=post};return hook_serial-1,hook_serial end
 UnregisterHook=function(path,pre,post)assert(pre and post);counts.unhook=counts.unhook+1;hooks[path]=nil end
 local M=dofile(root..'/server/entities.lua').new{root='fixture/',json=J,origin={X=0,Y=0,Z=0},session='lab-session',now=function()return clock end,
  read=function(k)return store[k]and clone(store[k])end,write=function(k,v)store[k]=clone(v)end}
 store['mc-state.json']={v=1,t='entity_snapshot',authority='mc_server',session='lab-session',epoch='mc-epoch',revision=1,unix=clock,
  entities={{id=MOB,kind='minecraft:zombie',category='mob',dimension='minecraft:overworld',x=0,y=64,z=0,yaw=0,width=.6,height=1.8,hp=20,max_hp=20,alive=true}}}
 M.tick();assert(M.running and counts.spawn==1,J.encode(M.status()))
 local function hit(id,source,targetId)return {v=1,t='entity_damage',authority='mc_server',id=gid(id),session='lab-session',target_epoch=M.epoch,source_epoch='mc-epoch',target=targetId or'pal:'..gid(0)..'/'..gid(4),source=source or MOB,amount=2,kind='minecraft:mob_attack'}end
 return {m=M,store=store,counts=counts,player=player,player_cp=player_cp,target=target,target_cp=target_cp,damage=damage,pc=pc,gs=gs,
  hit=hit,clock=function(v)clock=v end,hooks=hooks,proof={v=2,world_id='world-lab',server_session_id='lab-session',pal_uid=UID,mc_uuid=gid(5),session_id=gid(6),generation=1,expires_at=110,legacy=false}}
end

return {setup=setup,uid=UID,gid=gid,obj=obj}
