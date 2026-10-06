local root=assert(arg[1],'Repository palcraft root required')
local P=dofile(root..'/server/entity_protocol.lua')
local J=dofile(assert(arg[2],'JSON module path required'))
local n=0;local cases={}
local function test(name,f)local ok,why=pcall(f);assert(ok,name..': '..tostring(why));n=n+1;cases[#cases+1]=name end
local function bad(f)local ok=pcall(f);assert(not ok,'Expected rejection')end
local function clone(x)return J.decode(J.encode(x))end
local A='00000001-0000-0000-0000-000000000001';local B='00000002-0000-0000-0000-000000000002'
local SESSION='lab-session';local EPOCH='pal-epoch';local MC='mc-epoch'
local function hit(id)return {v=1,t='entity_damage',authority='mc_server',id=id or A,session=SESSION,target_epoch=EPOCH,source_epoch=MC,source='mc:'..A,target='pal:'..A..'/'..B,amount=3,kind='minecraft:mob_attack'}end
local function snapshot()return {v=1,t='entity_snapshot',authority='mc_server',session=SESSION,epoch=MC,revision=1,unix=100,entities={{id='mc:'..A,kind='minecraft:zombie',category='mob',dimension='minecraft:overworld',x=1,y=64,z=1,yaw=0,width=.6,height=1.8,hp=20,max_hp=20,alive=true}}}end
test('stable identities reject recyclable handles',function()assert(P.entity_id('mc:'..A));assert(P.entity_id('pal:'..A..'/'..B));assert(not P.entity_id('pal:123'));assert(not P.uuid('../event'))end)
test('valid server snapshot and hit',function()assert(P.validate_snapshot(snapshot(),SESSION,100));assert(P.validate_hit(hit(),SESSION,EPOCH,MC,'mc_server'))end)
test('observer cannot submit damage',function()local q=hit();q.authority='pal_client';bad(function()P.validate_hit(q,SESSION,EPOCH,MC,'mc_server')end)end)
test('stale session and both authority epochs reject',function()for _,k in ipairs({'session','source_epoch','target_epoch'})do local q=hit();q[k]='old';bad(function()P.validate_hit(q,SESSION,EPOCH,MC,'mc_server')end)end end)
test('damage bounds and non-finite values reject',function()for _,v in ipairs({0,-1,10001,math.huge,-math.huge})do local q=hit();q.amount=v;bad(function()P.validate_hit(q,SESSION,EPOCH,MC,'mc_server')end)end;local q=hit();q.amount=0/0;bad(function()P.validate_hit(q,SESSION,EPOCH,MC,'mc_server')end)end)
test('same-engine direction rejects',function()local q=hit();q.target='mc:'..B;bad(function()P.validate_hit(q,SESSION,EPOCH,MC,'mc_server')end)end)
test('snapshot duplicate IDs reject',function()local q=snapshot();q.entities[2]=clone(q.entities[1]);bad(function()P.validate_snapshot(q,SESSION,100)end)end)
test('stale snapshot rejects',function()bad(function()P.validate_snapshot(snapshot(),SESSION,104)end)end)
test('non-finite coordinates reject',function()local q=snapshot();q.entities[1].x=0/0;bad(function()P.validate_snapshot(q,SESSION,100)end)end)
test('durable intent precedes native invocation and replay preserves result',function()
 local store={};local calls=0
 local m=P.new{session=SESSION,epoch=EPOCH,now=function()return 100 end,read=function(k)return store[k]end,write=function(k,v)store[k]=clone(v)end,apply=function(q)calls=calls+1;assert(store['pal-result-'..q.id..'.json'].status=='in_flight');return {ok=true,before_hp=10,after_hp=7}end}
 assert(m.snapshot(snapshot()));assert(not m.snapshot(snapshot()));local r=m.hit(hit());assert(r.ok and calls==1);assert(m.hit(hit()).after_hp==7 and calls==1)
 local q=hit();q.amount=4;assert(m.hit(q).status=='id_conflict'and calls==1)
end)
test('crash after native call never automatically applies again',function()
 local store={};local calls=0
 local m=P.new{session=SESSION,epoch=EPOCH,now=function()return 100 end,read=function(k)return store[k]end,write=function(k,v)store[k]=clone(v)end,apply=function(q)calls=calls+1;error('simulated native crash after mutation')end}
 m.snapshot(snapshot());assert(m.hit(hit()).status=='native_error');assert(m.hit(hit()).status=='native_error'and calls==1)
end)
test('crash while writing final receipt leaves visible uncertain intent',function()
 local store={};local calls,writes=0,0
 local m=P.new{session=SESSION,epoch=EPOCH,now=function()return 100 end,read=function(k)return store[k]end,write=function(k,v)writes=writes+1;if writes==2 then error('lost final receipt')end;store[k]=clone(v)end,apply=function()calls=calls+1;return {ok=true}end}
 m.snapshot(snapshot());bad(function()m.hit(hit())end);assert(m.hit(hit()).status=='in_flight'and calls==1)
end)
test('storage failure prevents native mutation',function()
 local calls=0;local m=P.new{session=SESSION,epoch=EPOCH,now=function()return 100 end,read=function()end,write=function()error('disk full')end,apply=function()calls=calls+1 end}
 m.snapshot(snapshot());bad(function()m.hit(hit())end);assert(calls==0)
end)
test('old hit after restart cannot target new incarnation',function()
 local calls=0;local m=P.new{session=SESSION,epoch='new-pal-boot',now=function()return 100 end,read=function()end,write=function()end,apply=function()calls=calls+1 end}
 m.snapshot(snapshot());assert(not m.hit(hit()).ok and calls==0)
end)
print(J.encode({ok=true,suite='entity_protocol',tests=n,cases=cases,real_game_runtime_verified=false}))
