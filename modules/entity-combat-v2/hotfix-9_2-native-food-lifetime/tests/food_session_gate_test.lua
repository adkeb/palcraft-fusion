local root=assert(arg[1]);local J=dofile(assert(arg[2]));local cases={};local real_dofile=dofile
local function test(name,f)local ok,why=pcall(f);assert(ok,name..': '..tostring(why));cases[#cases+1]=name end
local function setup()
 local c={factories=0,readiness=0,apply=0}
 dofile=function(path)
  if path==root..'/server/food_native.lua'then return {new=function()
   c.factories=c.factories+1
   return {confirmed=0,readiness=function(e)assert(e.player and e.actor:IsInitialized());c.readiness=c.readiness+1;return true end,
    apply=function(q,e)c.apply=c.apply+1;return {ok=true,status='fixture_only'}end,tick=function()end,stop=function()end,status=function()return {}end}
  end}end
  return real_dofile(path)
 end
 local F=real_dofile(root..'/tests/entity_authority_fixture.lua');local s=F.setup()
 s.counts_food=c;s.fixture=F
 local proof=s.proof
 s.store['../auth/authenticated-sessions.json']={v=2,updated_unix=100,server_session_id='lab-session',world_id='world-lab',sessions={proof}}
 local function present()
  s.store['mc-state.json'].player_vitals={{mc_uuid=proof.mc_uuid,pal_uid=proof.pal_uid,authority='pal_server'}}
 end
 s.present=present
 return s
end
test('a fresh MC process with an empty authenticated player presence creates no native food worker',function()
 local s=setup();s.m.tick();assert(s.counts_food.factories==0 and s.counts_food.readiness==0)
 local food=s.store['pal-state.json'].food;assert(food.enabled and #food.ready_players==0 and food.phase=='waiting_verified_mc_session')
end)
test('a fresh authenticated MC player enables only its real native provider',function()
 local s=setup();s.present();s.m.tick();assert(s.counts_food.factories==1 and s.counts_food.readiness==1 and s.counts_food.apply==0)
 local food=s.store['pal-state.json'].food;assert(#food.ready_players==1 and food.ready_players[1]=='pal:'..s.proof.pal_uid..'/'..s.fixture.gid(2))
end)
test('empty or stale authentication cannot instantiate native food on first Pal join',function()
 local s=setup();s.present();s.store['../auth/authenticated-sessions.json'].sessions={};s.m.tick();assert(s.counts_food.factories==0)
 s.store['../auth/authenticated-sessions.json'].sessions={s.proof};s.store['../auth/authenticated-sessions.json'].updated_unix=80;s.m.tick();assert(s.counts_food.factories==0)
end)
test('a stale MC snapshot cannot instantiate native food even with valid authentication',function()
 local s=setup();s.present();s.store['mc-state.json'].unix=90;s.m.tick();assert(s.counts_food.factories==0)
end)
test('wrong world or mismatched MC to Pal player identities fail closed',function()
 local s=setup();s.present();s.store['../auth/authenticated-sessions.json'].world_id='other';s.m.tick();assert(s.counts_food.factories==0)
 s.store['../auth/authenticated-sessions.json'].world_id='world-lab';s.store['mc-state.json'].player_vitals[1].pal_uid=s.fixture.gid(99);s.m.tick();assert(s.counts_food.factories==0)
end)
test('an expired authenticated connection cannot instantiate native food',function()
 local s=setup();s.present();s.store['../auth/authenticated-sessions.json'].sessions[1].expires_at=99;s.m.tick();assert(s.counts_food.factories==0)
end)
test('a previously accepted paid receipt still requires current MC player presence',function()
 local s=setup();s.present();s.m.tick();local id=s.fixture.gid(60)
 s.store['mc-foods.json']={session='lab-session',epoch='mc-epoch',ids={id}}
 s.store['mc-food-'..id..'.json']={v=1,t='entity_consume',authority='mc_server',id=id,session='lab-session',source_epoch='mc-epoch',target_epoch=s.m.epoch,
  source='mc:'..s.proof.mc_uuid,target='pal:'..s.proof.pal_uid..'/'..s.fixture.gid(2),player_session=s.proof,item='minecraft:bread',before_count=2,after_count=1,
  consumed_count=1,vanilla_completed=true,nutrition=5,saturation=6,effects={},effects_json='[]'}
 s.store['mc-state.json'].player_vitals={};s.m.tick();assert(s.counts_food.apply==0)
 assert(s.store['pal-food-result-'..id..'.json'].status=='needs_recovery_paid_not_fed')
end)
dofile=real_dofile
print(J.encode({ok=true,suite='food_verified_session_gate_targeted',tests=#cases,cases=cases,real_game_runtime_verified=false}))
