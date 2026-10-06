-- Real feature modules with a small reflected-engine fixture. No game process, port or RPC.
local root,codec,tmp,out=assert(arg[1]),assert(arg[2]),assert(arg[3]),assert(arg[4])
local server_entity_dir=arg[5]or(root..'/server')
local J=dofile(codec);local cases={};local n=0;local clock=100
local function clone(x)return J.decode(J.encode(x))end
local function test(name,f)local ok,err=pcall(f);assert(ok,name..': '..tostring(err));n=n+1;cases[#cases+1]=name end
local function write(path,value)local f=assert(io.open(path,'wb'));f:write(J.encode(value));f:close()end
local function read(path)local f=assert(io.open(path,'rb'));local v=J.decode(f:read('*a'));f:close();return v end
local function g(a)return{A=a,B=0,C=0,D=0}end
local function guid(v)return('%08x-0000-0000-0000-000000000000'):format(v.A)end
local function id(a)return guid(g(a))end
local PAL,MC,SID=id(1),id(2),id(3);local EPOCH=id(4);local BOOT='lab-session';local WORLD='world-lab'
local rows={};local address=1000
local function object(name,methods)
 address=address+1;local o=methods or{};o.address=address
 o.IsValid=function()return true end;o.HasAuthority=function()return true end
 o.GetFullName=function()return name end;o.GetAddress=function(s)return s.address end;return o
end
local gs=object('AuthorityGameState',{ServerSessionId=BOOT,GetWorldSaveDirectoryName=function()return WORLD end})
local ip=object('PlayerParameter',{GetShieldHP=function()return 0 end,GetShieldMaxHP=function()return 100 end,
 GetGroupId=function()return g(0)end,GetCharacterID=function()return'Player'end})
local cp=object('PlayerComponent',{GetIndividualParameter=function()return ip end,GetHP=function()return 1 end,
 GetMaxHP=function()return 2370 end,GetFullStomach=function()return 0 end,GetMaxFullStomach=function()return 100 end,
 IsDead=function()return false end,IsDying=function()return false end})
local pawn=object('PlayerPawn',{GetCharacterParameterComponent=function()return cp end,
 K2_GetActorLocation=function()return{X=0,Y=0,Z=90}end,K2_GetActorRotation=function()return{Yaw=0,Pitch=0,Roll=0}end,
 IsA=function(_,name)return name=='/Script/Pal.PalPlayerCharacter'end})
pawn.CapsuleComponent=object('Capsule',{GetScaledCapsuleHalfHeight=function()return 90 end,GetScaledCapsuleRadius=function()return 30 end})
local pc=object('PalController',{Pawn=pawn,GetPlayerUId=function()return g(1)end,GetWorld=function()return gs end,
 Player=object('PalLocalPlayer /Engine/Transient.Personal')})
pawn.GetController=function()return pc end
local individual=object('SavedIndividual',{GetIndividualID=function()return{PlayerUId=g(1),InstanceId=g(5)}end})
local account=object('SavedAccount',{IndividualHandle=individual})
local manager=object('CharacterManager',{GetIndividualHandleFromCharacterParameter=function()return individual end})
local utilities={
 ['/Script/Pal.Default__PalUtility']=object('Utility',{GetCharacterManager=function()return manager end}),
 ['/Script/Pal.Default__FixedPoint64MathLibrary']=object('Fixed',{Convert_FixedPoint64ToFloat=function(_,v)return v end}),
 ['/Script/Engine.Default__KismetGuidLibrary']=object('Guid',{NewGuid=function()return g(6)end})}
rows.PalGameStateInGame={gs};rows.PalPlayerAccount={account};rows.PalPlayerController={pc};rows.PalCharacter={pawn}
rows.PalDatabaseCharacterParameter={object('Database')}
local hooks,unhooks=0,0
IsInGameThread=function()return true end
FindAllOf=function(name)return rows[name]or{}end
StaticFindObject=function(name)return utilities[name]or object('ReflectedFunction '..name)end
RegisterHook=function()hooks=hooks+1;return hooks*2-1,hooks*2 end
UnregisterHook=function()unhooks=unhooks+1 end
os.time=function()return clock end
local R={guid_to_string=guid};local Compose=dofile(root..'/runtime/compose.lua');local Session=dofile(root..'/runtime/session.lua')
local proof={v=2,legacy=false,world_id=WORLD,pal_uid=PAL,mc_uuid=MC,mc_name='Player',server_session_id=BOOT,
 session_id=SID,generation=1,expires_at=1000}
local presence={v=2,authority=true,world_id=WORLD,server_session_id=BOOT,updated_unix=100,
 players={{pal_uid=PAL,possessed=true,saved_account=true}}}
local sessions={v=2,world_id=WORLD,server_session_id=BOOT,mc_epoch=EPOCH,updated_unix=100,sessions={proof}}
test('strict registry keeps exact UID and true MC epoch',function()
 local r=Session.registry(sessions,presence,100);assert(r.by_mc[MC].pal_uid==PAL and r.by_mc[MC].mc_epoch==EPOCH)
end)
test('stale boot epoch and ambiguous bindings are rejected',function()
 for _,change in ipairs({function(q)q.updated_unix=90 end,function(q)q.server_session_id='old'end,
  function(q)q.mc_epoch=nil end,function(q)q.sessions[1].legacy=true end,function(q)q.sessions[2]=clone(q.sessions[1])end})do
  local q=clone(sessions);change(q);assert(not pcall(Session.registry,q,presence,100))
 end
end)
test('host proof never invents MC authority epoch',function()
 local status={schema=1,protocol=2,state='bound',authenticated_host=true,updated_unix=100,identity={world_id=WORLD,pal_uid=PAL,mc_uuid=MC,mc_name='Player'},
  server_session_id=BOOT,session_id=SID,generation=1,expires_at=1000}
 local expected=clone(status.identity);expected.server_session_id=BOOT
 local h=Session.host(status,expected,100);assert(h.mc_epoch==nil and h.mc_epoch_verified==false)
 status.generation=0;assert(not pcall(Session.host,status,expected,100))
end)
test('lifecycle starts once respects cadence and stops in reverse order',function()
 local trace={};local c=Compose.new{}
 for i,name in ipairs({'a','b'})do c:register(name,{depends=i==2 and{'a'}or{},interval_ms=250,
  factory=function()trace[#trace+1]='start_'..name;return{}end,
  tick=function()trace[#trace+1]='tick_'..name end,stop=function()trace[#trace+1]='stop_'..name end})end
 assert(c:tick(0,{}));c:tick(16,{});c:tick(249,{});c:tick(250,{})
 assert(c.features.a.calls.start==1 and c.features.a.calls.tick==2)
 assert(c:stop('disconnect'));assert(trace[#trace-1]=='stop_b'and trace[#trace]=='stop_a')
end)
test('module start is distinct from gameplay readiness',function()
 local c=Compose.new{};c:register('authority',{factory=function()return{}end,status=function()return{ready=false}end,is_ready=function(s)return s.ready end})
 c:tick(0,{});assert(c:status().modules_started and not c:status().ready)
end)
test('failures and disabled operations cannot report success',function()
 local c=Compose.new{}
 c:register('missing',{enabled=false,disabled_reason='native_not_ready',factory=function()error('must not load')end,routes={native=function()return{ok=true}end}})
 c:register('broken',{factory=function()return{}end,tick=function()error('actual_error')end,routes={broken=function()return{ok=true}end}})
 c:tick(0,{});local handled,r=c:dispatch('native',{});assert(handled and r.ok==false and r.reason=='native_not_ready')
 handled,r=c:dispatch('broken',{});assert(handled and r.ok==false and r.reason:find('actual_error',1,true))
 assert(not c:status().ready and c.features.broken.calls.stop==1)
end)
local companion={running=true,origin={X=0,Y=0,Z=0},actors={},queue={},queue_head=1,changes=0}
companion.status=function()return{running=true,blocks=0}end
local ForeignJSON=dofile(codec)
companion.status_json=function()return ForeignJSON.encode({running=true,blocks=0,pending_view={pos=ForeignJSON.array{0,64,0}}})end
companion.set_world_observer=function(observer)companion.observer=observer end
write(tmp..'/auth/authenticated-sessions.json',sessions)
write(tmp..'/entities/mc-state.json',{v=1,t='entity_snapshot',authority='mc_server',session=BOOT,epoch=EPOCH,revision=1,unix=100,entities={},
 player_vitals={{pal_uid=PAL,mc_uuid=MC,hearts=20/2370,max_hearts=20}}})
local server=dofile(root..'/server/features.lua').new{runtime_dir=root..'/runtime/',json=J,readers=R,
 bridge_root=tmp,auth_root=tmp..'/auth/',origin={X=0,Y=0,Z=0},companion=function()return companion end,
 load=function(name)return dofile((name=='entities'and server_entity_dir or(root..'/server'))..'/'..name..'.lua')end}
test('server features invokes real presence and entity authority once',function()
 local good=server:tick(0);assert(good,J.encode(server:status()));assert(hooks==2 and _G.PalCraftEntityAuthority)
 local snapshot=read(tmp..'/entities/pal-state.json');assert(snapshot.entities[1].hp==1 and snapshot.entities[1].max_hp==2370)
 assert(snapshot.entities[1].player_uid==PAL and read(tmp..'/auth/pal-presence.json').players[1].pal_uid==PAL)
 server:tick(100);assert(server.composition.features.entities.calls.tick==1)
 server:tick(250);assert(server.composition.features.entities.calls.tick==2 and hooks==2)
end)
test('server resolver and disabled exchange use the unified dispatcher',function()
 local b=server.resolve(MC);assert(b.pc==pc and b.pal_uid==PAL and b.mc_epoch==EPOCH)
 local handled,q=server:dispatch('palcraft_exchange',{action='debit'},{id=id(9)});assert(handled and q.ok==false and q.status=='feature_not_ready')
 assert(server.composition.features.exchange.calls.start==0)
end)
local host={schema=1,protocol=2,state='bound',identity={world_id=WORLD,pal_uid=PAL,mc_uuid=MC,mc_name='Player'},server_session_id=BOOT,
 session_id=SID,generation=1,expires_at=1000,authenticated_host=true,updated_unix=100}
write(tmp..'/session-bind-status.json',host)
local meta={schema=1,state='bound',stale=false,updated_unix=100,identity=host.identity,server_session_id=BOOT,host_session_id=SID,generation=1}
write(tmp..'/entities/binding-meta.json',meta)
local client=dofile(root..'/client/features.lua').new{runtime_dir=root..'/runtime/',json=J,bridge_root=tmp,identity=host.identity,
 load=function(name)return dofile(root..'/client/'..name..'.lua')end}
local ctx={pc=pc,identity={server_session_id=BOOT},collisions=companion,input={}}
test('client features calls the real observer and reads Pal 1/2370 vitals',function()
 assert(client:tick(0,ctx));assert(_G.PalCraftAcceptanceVitals and _G.PalCraftEntityObserver)
 local v=_G.PalCraftAcceptanceVitals(pc);assert(v.ok and v.pal.hp==1 and v.pal.max_hp==2370 and math.abs(v.expected_mc_health-20/2370)<1e-12)
 assert(client:status().ready and client.composition.features.entities.calls.start==1)
 client:tick(16,ctx);assert(client.composition.features.entities.calls.tick==1)
end)
test('foreign companion JSON arrays survive both feature status encoders',function()
 assert(J.decode(J.encode(server:status())).features[3].status.pending_view.pos[2]==64)
 assert(J.decode(J.encode(client:status())).features[2].status.pending_view.pos[2]==64)
end)
test('new host generation rejects old mirrored snapshots',function()
 host.generation=2;write(tmp..'/session-bind-status.json',host);client:tick(250,ctx)
 assert(client.composition.features.entities.calls.start==2 and client.composition.features.entities.calls.stop==1)
 local v=_G.PalCraftAcceptanceVitals(pc);assert(not v.ok and v.status=='authority_stale')
 assert(not client:status().ready)
 meta.generation=2;write(tmp..'/entities/binding-meta.json',meta);client:tick(500,ctx);assert(_G.PalCraftAcceptanceVitals(pc).ok)
end)
test('disconnect clears old per-player observers and QA globals',function()
 host.state='unbound';host.authenticated_host=false;write(tmp..'/session-bind-status.json',host);client:tick(750,ctx)
 assert(not client.binding and not _G.PalCraftAcceptanceVitals and not _G.PalCraftEntityObserver)
 assert(client.composition.features.host.phase=='waiting'and not client:status().ready)
end)
test('server stop releases the real native hooks once',function()
 assert(server:stop('fixture_done'));assert(unhooks==2 and _G.PalCraftEntityAuthority==nil and _G.PalCraftSessionAuth==nil)
 assert(server:stop('fixture_done'));assert(unhooks==2)
end)
test('per-block readiness requires full snapshot and exact native revision',function()
 local World=dofile(root..'/server/world_compat.lua');local world=World.new{}
 local shape={at={0,64,0},op='upsert',id='minecraft:oak_planks',state='',boxes={{0,0,0,1,1,1}},solid=true,visible=true,fluid={kind='none'}}
 local bounds={0,64,0,1,65,1}
 world:ingest{t='blocks',v=2,session=EPOCH,seq=1,dim='minecraft:overworld',ops={},lifecycle={}}
 companion.world=world;companion.set_view=function(d,p)world:set_view(d,p)end
 local verified=false
 local view=dofile(root..'/runtime/companion_view.lua').new{companion=companion,encode_geometry=J.encode,verify_native=function()
  return{collision_committed=verified,collision_verified=verified,visual_committed=false,evidence='fixture_not_live'}
 end}
 local ticket=view.prepare_view{world_session=EPOCH,dim='minecraft:overworld',view=1,generation=1,mode='server',required_bounds=bounds,
  mapping={origin=companion.origin,region_id='home',scale=100,y_origin=64}}
 assert(not view.readiness(ticket).ready) -- Empty queue does not prove coverage.
 shape.snapshot='snapshot'
 world:ingest{t='blocks',v=2,session=EPOCH,seq=2,dim='minecraft:overworld',ops={shape},lifecycle={{op='snapshot_begin',snapshot='snapshot',at={0,0},bounds=bounds}}}
 world:ingest{t='blocks',v=2,session=EPOCH,seq=3,dim='minecraft:overworld',ops={},lifecycle={{op='snapshot_end',snapshot='snapshot',at={0,0},bounds=bounds}}}
 assert(not view.readiness(ticket).ready)
 local expected=world:get('minecraft:overworld',0,64,0)
 companion.actors['0:64:0']={signature=J.encode(expected),handles={100}}
 assert(not view.readiness(ticket).ready)
 verified=true;companion.changes=1;assert(view.readiness(ticket).ready and view.activate(ticket))
 assert(view.release(ticket))
end)
test('unverified chunk factory cannot create a second world',function()
 local chunks=dofile(root..'/runtime/chunks.lua');local called=false
 assert(not pcall(chunks.new,{client_dir=root..'/client/',json=J,models={},context={},origin={},collision_verified=false,
  install_consumer=function()called=true;return true end}))
 assert(not called)
end)
write(out,{schema_version=1,passed=true,cases=n,names=cases,mode='offline_reflected_fixture',real_modules={
 'server/features.lua','server/session-auth.lua','server/entities.lua','client/features.lua','client/entities.lua','server/world_compat.lua',
 'runtime/compose.lua','runtime/session.lua','runtime/companion_view.lua'},game_engine_validated=false,runtime_mutations=false})
print(J.encode({passed=true,cases=n,out=out}))
