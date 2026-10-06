local root=assert(arg[1]);local J=dofile(assert(arg[2]));local P=dofile(root..'/server/entity_protocol.lua');local F=dofile(root..'/server/food_protocol.lua')
local function clone(v)return J.decode(J.encode(v))end
local A='00000001-0000-0000-0000-000000000001';local B='00000002-0000-0000-0000-000000000002';local cases={}
local function test(n,f)local ok,e=pcall(f);assert(ok,n..': '..tostring(e));cases[#cases+1]=n end
local function meal()
 return {v=1,t='entity_consume',authority='mc_server',id=A,session='lab',source_epoch='mc',target_epoch='pal',source='mc:'..A,target='pal:'..A..'/'..B,
  item='minecraft:bread',before_count=3,after_count=2,consumed_count=1,vanilla_completed=true,creative=false,nutrition=5,saturation=6,effects={},effects_json='[]',player_session={mc_uuid=A,session_id=B,generation=1}}
end
local function setup(apply,write)
 local store={};local calls=0
 local m=F.new{protocol=P,session='lab',epoch='pal',source_epoch=function()return'mc'end,read=function(k)return store[k]end,
  write=write or function(k,v)store[k]=clone(v)end,apply=function(q)calls=calls+1;assert(store['pal-food-result-'..q.id..'.json'].status=='in_flight');return apply and apply(q)or{ok=true,before_full_stomach=0,after_full_stomach=25}end}
 return m,store,function()return calls end
end
test('one real vanilla count decrement permits one normal native effect',function()local m,s,n=setup();assert(m.consume(meal()).ok and n()==1);assert(m.consume(meal()).after_full_stomach==25 and n()==1)end)
test('same ID with different paid food is conflict',function()local m,s,n=setup();m.consume(meal());local q=meal();q.item='minecraft:apple';assert(m.consume(q).status=='id_conflict'and n()==1)end)
test('unpaid creative or cancelled consumption never feeds',function()for _,field in ipairs({'creative','vanilla_completed','after_count','consumed_count'})do local m,s,n=setup();local q=meal();if field=='creative'then q[field]=true elseif field=='vanilla_completed'then q[field]=false else q[field]=3 end;assert(not m.consume(q).ok and n()==0)end end)
test('stale native or MC generation epoch does not feed',function()for _,field in ipairs({'source_epoch','target_epoch','session'})do local m,s,n=setup();local q=meal();q[field]='stale';assert(not m.consume(q).ok and n()==0)end end)
test('native crash preserves paid uncertain intent without another consume',function()local m,s,n=setup(function()error('native failure')end);assert(m.consume(meal()).status=='needs_recovery_paid_not_fed');m.consume(meal());assert(n()==1)end)
test('storage failure occurs before native nutrition',function()local m,s,n=setup(nil,function()error('disk failure')end);assert(not pcall(m.consume,meal())and n()==0)end)
test('malformed food status cannot modify native state',function()local m,s,n=setup();local q=meal();q.effects={{id='minecraft:poison',amplifier=0,duration=math.huge}};assert(not m.consume(q).ok and n()==0)end)
test('status effects are part of replay identity',function()local m,s,n=setup();m.consume(meal());local q=meal();q.effects={{id='minecraft:hunger',amplifier=0,duration=600}};q.effects_json=J.encode(q.effects);assert(m.consume(q).status=='id_conflict'and n()==1)end)
print(J.encode({ok=true,suite='food_protocol_v2',cases=cases,tests=#cases,real_game_runtime_verified=false,execution_mode='night_low_power'}))
