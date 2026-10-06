-- Models the actual stale-receiver failure boundary. No UE/native runtime claim.
local root=assert(arg[1]);local J=dofile(assert(arg[2]));local baseline=assert(arg[3]);local cases={}
local function test(name,f)local ok,why=pcall(f);assert(ok,name..': '..tostring(why));cases[#cases+1]=name end
local next_address=10
local function object(class,p)
 p=p or{};next_address=next_address+1;p.address=next_address;p.class=class;p.valid=true
 p.IsValid=function(s)return s.valid end;p.GetAddress=function(s)return s.address end
 p.IsA=function(s,c)return s.class==c end;p.GetOuter=function(s)return s.outer end
 return p
end
local function setup(path)
 local c={construct_processor=0,construct_data=0,can_use=0,use=0,manager_reads=0};local t=100
 IsInGameThread=function()return true end;FName=function(s)return {ToString=function()return s end}end
 local gs=object('gs',{HasAuthority=function()return true end})
 local fixed=object('fixed',{Convert_FixedPoint64ToFloat=function(_,v)return v.Value end})
 local p={id='pal:fixture',player=true,actor=object('actor',{IsInitialized=function()return true end}),
  cp=object('cp',{hp=1,stomach=0,GetHP=function(s)return {Value=s.hp}end,GetMaxHP=function()return {Value=2370}end,
   GetFullStomach=function(s)return s.stomach end,GetMaxFullStomach=function()return 100 end,IsDead=function()return false end,IsDying=function()return false end}),
  ip=object('ip',{SetDecreaseFullStomachRates=function()end}),handle=object('handle',{GetIndividualID=function()return {PlayerUId={A=1,B=0,C=0,D=1},InstanceId={A=2,B=0,C=0,D=2}}end})}
 local manager,current,constructed,used_data
 local function processor(owner)
  return object('/Script/Pal.PalItemUseProcessor_CommonEffectToIndividualParameter',{outer=owner,
   CanUseItemToCharacter=function(s,d,id)assert(s.valid,'member lookup on GC-freed CanUse receiver');c.can_use=c.can_use+1;return true end,
   UseItemToCharacter_ServerInternal=function(s,d,id)assert(s==current,'stale processor reused');c.use=c.use+1;used_data=d;p.cp.stomach=p.cp.stomach+d:GetRestoreSatiety();return true end})
 end
 local function rotate()
  if current then current.valid=false end
  manager=object('/Script/Pal.PalItemIDManager');current=processor(manager)
  manager.ItemUseProcessorMap={ForEach=function(_,callback)callback({}, {get=function()return current end})end}
 end
 rotate()
 local utility=object('utility',{GetItemIDManager=function(_,world)assert(world==gs);c.manager_reads=c.manager_reads+1;return manager end})
 StaticFindObject=function(path)if path=='/Script/Pal.Default__PalUtility'then return utility end;return object(path)end
 StaticConstructObject=function(class,outer,name,flags,internal)
  assert(flags==64 and internal==0,'No root flag or raw memory changes')
  if class.class:find('CommonEffect',1,true)then c.construct_processor=c.construct_processor+1;constructed=processor(outer);return constructed end
  assert(outer==manager or outer==gs);c.construct_data=c.construct_data+1
  return object('/Script/Pal.PalStaticConsumeItemData',{GetRestoreSatiety=function(s)return s.RestoreSatiety end,GetRestoreHP=function(s)return s.RestoreHP end})
 end
 local m=dofile(path).new{game_state=gs,epoch='00000001-0000-0000-0000-000000000001',fixed=fixed,now=function()return t end}
 return {m=m,p=p,c=c,rotate=rotate,gc=function()if constructed then constructed.valid=false end;if used_data then used_data.valid=false end end,
  current=function()return current end,wrong_owner=function()current.outer=gs end,missing=function()manager.ItemUseProcessorMap.ForEach=function()end end}
end
local function q()return {id='00000003-0000-0000-0000-000000000003',item='minecraft:bread',nutrition=5,saturation=6,effects={}}end
test('frozen baseline retains a constructor receiver then uses it after simulated UE GC',function()
 local s=setup(baseline);assert(s.c.construct_processor==1);s.gc();assert(not s.m.readiness(s.p));assert(s.m.errors[s.p.id]:find('GC%-freed'))
end)
test('new factory and availability construct no processor or food and invoke no CanUse',function()
 local s=setup(root..'/server/food_native.lua');assert(s.c.construct_processor==0 and s.c.manager_reads==0)
 assert(s.m.readiness(s.p));assert(s.c.construct_data==0 and s.c.can_use==0 and s.c.use==0 and s.p.cp.hp==1)
end)
test('engine owner replacement between callbacks reacquires the current receiver',function()
 local s=setup(root..'/server/food_native.lua');assert(s.m.readiness(s.p));s.rotate();local r=s.m.apply(q(),s.p)
 assert(r.ok and s.c.can_use==1 and s.c.use==1 and s.c.construct_processor==0 and s.p.cp.hp==1)
end)
test('temporary food data is never reused after a tick or simulated collection',function()
 local s=setup(root..'/server/food_native.lua');assert(s.m.apply(q(),s.p).ok);s.gc();s.rotate();assert(s.m.apply(q(),s.p).ok)
 assert(s.c.construct_data==2 and s.c.construct_processor==0 and s.c.use==2)
end)
test('a processor with the wrong native owner fails closed before native item use',function()
 local s=setup(root..'/server/food_native.lua');s.wrong_owner();assert(not s.m.readiness(s.p));assert(not pcall(s.m.apply,q(),s.p));assert(s.c.can_use==0 and s.c.use==0 and s.c.construct_data==0)
end)
test('an absent engine-owned provider remains pending without a replacement constructor',function()
 local s=setup(root..'/server/food_native.lua');s.missing();assert(not s.m.readiness(s.p));assert(s.c.construct_processor==0 and s.c.construct_data==0)
end)
test('availability is explicitly distinct from native effect verification',function()
 local s=setup(root..'/server/food_native.lua');assert(s.m.readiness(s.p));local r=s.m.status()
 assert(not r.native_effect_verified and r.readiness_scope=='owned_provider_available_exact_item_CanUse_only_on_paid_request')
end)
print(J.encode({ok=true,suite='food_native_lifetime_targeted',tests=#cases,cases=cases,real_game_runtime_verified=false}))
