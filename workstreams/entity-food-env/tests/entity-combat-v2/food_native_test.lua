local root=assert(arg[1]);local J=dofile(assert(arg[2]));local cases={}
local function test(n,f)local ok,e=pcall(f);assert(ok,n..': '..tostring(e));cases[#cases+1]=n end
local function object(p)p=p or{};p.IsValid=function()return true end;return p end
local function setup()
 local t=100;local calls=0;local credits=0;IsInGameThread=function()return true end;FName=function(s)return{ToString=function()return s end}end
 local gs=object();local fixed=object{Convert_FixedPoint64ToFloat=function(_,v)return v.Value end}
 local target={id='pal:fixture',player=true,cp=object{hp=1,stomach=0,GetMaxFullStomach=function()return 100 end,
  GetFullStomach=function(s)return s.stomach end,GetHP=function(s)return{Value=s.hp}end,GetMaxHP=function()return{Value=2370}end,IsDead=function()return false end,IsDying=function()return false end},
  ip=object{rates={},SetDecreaseFullStomachRates=function(s,k,r)s.rates[k:ToString()]=r end,RemoveDecreaseFullStomachRates=function(s,k)s.rates[k:ToString()]=nil end},
  handle=object{GetIndividualID=function()return{PlayerUId={A=1,B=0,C=0,D=1},InstanceId={A=2,B=0,C=0,D=2}}end},actor=object()}
 target.actor.StatusComponent=object{AddStatusParameter=function(s,id,p)s.last=id;s.duration=p.GeneralFloatValue end,GetExecutionStatus=function(s,id)return object{Duration=s.duration}end}
 local nv=object{enabled=false,GetAddress=function()return 90 end,IsNightVisionEnabled_ForServer=function(s)return s.enabled end,SetNightVisionEnabled_ForServer=function(s,v)s.enabled=v end,SetNightVisionEnabled_ToClient=function(s,v,w)s.client=v end}
 target.actor.GetController=function()return object{BP_PalNightVisionComponent=nv}end;target.nv=nv
 StaticFindObject=function(path)return object{path=path}end
 StaticConstructObject=function(class,outer,name,flags)
  assert(outer==gs and flags==64)
  if class.path:find('CommonEffect',1,true)then return object{CanUseItemToCharacter=function()return true end,UseItemToCharacter_ServerInternal=function(_,d,id)
   calls=calls+1;target.cp.stomach=math.min(100,target.cp.stomach+d:GetRestoreSatiety());target.cp.hp=math.min(2370,target.cp.hp+d:GetRestoreHP());return true
  end}end
  return object{GetRestoreSatiety=function(s)return s.RestoreSatiety end,GetRestoreHP=function(s)return s.RestoreHP end}
 end
 local m=dofile(root..'/server/food_native.lua').new{game_state=gs,epoch='00000001-0000-0000-0000-000000000001',fixed=fixed,now=function()return t end}
 return m,target,function()return calls end,function(v)t=v end
end
local function q()return{id='00000003-0000-0000-0000-000000000003',item='minecraft:bread',nutrition=5,saturation=6,effects={}}end
test('readiness does not feed or heal the existing 1HP player',function()local m,p,n=setup();assert(m.readiness(p));assert(p.cp.hp==1 and p.cp.stomach==0 and n()==0)end)
test('paid bread uses ordinary processor, no native stack credit or direct HP setter',function()local m,p,n=setup();local r=m.apply(q(),p);assert(r.ok and r.after_full_stomach==25 and p.cp.hp==1 and n()==1 and r.native_items_credited==0)end)
test('saturation modifies only existing metabolism and expires',function()local m,p,n,t=setup();m.apply(q(),p);assert(next(p.ip.rates));t(281);m.tick();assert(not next(p.ip.rates))end)
test('actual hunger outcome adjusts native metabolism with one effect expiry',function()local m,p,n,t=setup();local e=q();e.effects={{id='minecraft:hunger',duration=600,amplifier=0}};local r=m.apply(e,p);assert(r.ok and #r.effects==2);t(131);m.tick();local count=0;for _ in pairs(p.ip.rates)do count=count+1 end;assert(count==1)end)
test('actual poison status uses native status component',function()local m,p,n=setup();local e=q();e.effects={{id='minecraft:poison',duration=100,amplifier=0}};local r=m.apply(e,p);assert(r.ok and p.actor.StatusComponent.last==5 and r.effects[2].native=='PalStatusComponent:AddStatusParameter')end)
test('actual regeneration food maps paid healing through normal consume data',function()local m,p,n=setup();local e=q();e.effects={{id='minecraft:regeneration',duration=100,amplifier=1}};local r=m.apply(e,p);assert(r.ok and r.native_restore_hp==474 and p.cp.hp==475 and n()==1)end)
test('unmapped special status remains visible pending rather than fake applied',function()local m,p,n=setup();local e=q();e.effects={{id='minecraft:absorption',duration=2400,amplifier=0}};local r=m.apply(e,p);assert(r.ok and r.status=='applied_with_pending_status_equivalents'and #r.unsupported_effects==1)end)
test('stop removes only registered food metabolism modifiers',function()local m,p,n=setup();m.apply(q(),p);m.stop();assert(not next(p.ip.rates)and p.cp.hp==1)end)
test('paid night vision uses real native component and restores prior state on expiry',function()local m,p,n,t=setup();local e=q();e.effects={{id='minecraft:night_vision',duration=100,amplifier=0}};local r=m.apply(e,p);assert(r.ok and p.nv.enabled and p.nv.client and #r.unsupported_effects==0);t(106);m.tick();assert(not p.nv.enabled and not p.nv.client and p.cp.hp==1)end)
print(J.encode({ok=true,suite='food_native_boundary_mock_v2',tests=#cases,cases=cases,real_game_runtime_verified=false,execution_mode='night_low_power'}))
