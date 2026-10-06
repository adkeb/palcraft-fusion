local base,tmp=assert(arg[1]),assert(arg[2])
local J=dofile(base..'/native_renderer/candidate-v5/json.lua')
local Records=dofile(base..'/palcraft/runtime/records.lua')
local Wiring=dofile(base..'/palcraft/client/material_live_wiring.lua')
local count=0;local function check(ok,why)assert(ok,why);count=count+1 end
local function read(path)local f=assert(io.open(path,'rb'));local v=J.decode(f:read('*a'));f:close();return v end
local function write(path,value)local f=assert(io.open(path,'wb'));f:write(J.encode(value));f:close()end
local function object(t)t=t or{};function t:IsValid()return true end;function t:GetAddress()return 100 end;return t end
os.remove(tmp..'/command.json');os.remove(tmp..'/command.json.pending')
write(tmp..'/index.json',{version=1,textures={['textures/minecraft/block/oak_leaves.png']={path='textures/minecraft/block/oak_leaves.png.rgba',width=16,height=16,sha256=string.rep('a',64)}}})
local asset_root='D:/PalworldServer-LAN/PalCraft-Dev/bridge/models-v4-761ddea057ce/'
local commands=Records.commands{json=J,path=tmp..'/command.json'}
local original={texture='minecraft:block/oak_leaves',tint=0,alpha_mode='cutout',shade=false,vertices={},indices={}}
local blocks={}
local function position(x,y,z)return x..':'..y..':'..z end
local resumed={};local c={world={dimension='minecraft:overworld'}}
function c.world:get(_,x,y,z)return blocks[position(x,y,z)]end
function c.retry_material_block(block)resumed[#resumed+1]=block;return true end
local models={geometry=function(id,state,x,y,z)return{original}end}
local raw_geometry=models.geometry
local handlers={};local ticks=0;local p={}
function p.add_material_handler(accept,resolve)local h={accept=accept,resolve=resolve};handlers[#handlers+1]=h;return h end
function p.remove_material_handler(h)for i,v in ipairs(handlers)do if h==v then table.remove(handlers,i);return true end end;return false end
function p.tick()ticks=ticks+1 end;function p.stop()return true end
local inherited=object();local parent=object({MaterialDomain=0})
function parent:GetBlendMode()return 1 end;function parent:GetBaseMaterial()return self end
local imports,bakes,mids={},{},0
local material_options={json=J,bridge_root=tmp..'/',pixel_packages={[asset_root]={namespace='fixture',index_path='index.json'}},
 request_nonce='actual-command-fixture',send_query=commands.send,seconds=function()return 0 end,name=function(s)return s end,
 load_asset=function()return parent end,
 create_material=function()
  mids=mids+1;local m=object({params={}})
  function m:K2_GetTextureParameterValue()return inherited end
  function m:SetTextureParameterValue(k,v)self.params[k]=v end
  function m:SetScalarParameterValue()end;function m:SetVectorParameterValue()end
  return m
 end,
 import_texture=function(_,path)imports[#imports+1]=path;return object()end,
 bake_texture=function(input,output,w,h,rgb)bakes[#bakes+1]={input=input,output=output,rgb=rgb};return tmp..'/'..output end}
local wiring=Wiring.attach{models=models,pipeline=p,companion=c,material_options=material_options}
local scope={mc_uuid='fixture-local',world_session='fixture-world',dim='minecraft:overworld',view=1}
check(p.material_runtime==wiring and models.geometry~=raw_geometry,'factory actually installed geometry consumer')
p.bind_material_scope(scope)
for x=1,2 do blocks[position(x,64,0)]={id='minecraft:oak_leaves',state='persistent=true',properties={persistent='true'}}end
local a,why=models.geometry('minecraft:oak_leaves','persistent=true',1,64,0)
models.geometry('minecraft:oak_leaves','persistent=true',2,64,0)
check(a[1].material_pending and why=='actual_block_tint_pending'and original.material_pending==nil,'pending copied without mutating frozen geometry')
p.tick(.05,0);commands.tick()
local query=read(tmp..'/command.json');os.remove(tmp..'/command.json')
check(query.t=='material_tint_query'and #query.rows==2 and query.mc_uuid==scope.mc_uuid and query.view==1,'actual existing command queue sent scope and two biome coordinates')
local function reply(request,colors)
 local r={t='material_tint',v=1,mc_uuid=request.mc_uuid,world_session=request.world_session,dim=request.dim,view=request.view,
  source='minecraft:material_tint_v1',read_only=true,request_id=request.request_id,rows={}}
 for i,row in ipairs(request.rows)do r.rows[i]={id=row.id,x=row.x,y=row.y,z=row.z,key=row.key,
  tint_source=row.tint_role=='water'and'minecraft:biome_water_color'or'minecraft:block_tint_source.colorInWorld',tint_colors={['0']=colors[i]}}end
 return r
end
local event=reply(query,{0x91bd59,0x6a7039})
event.view=2;check(not p.accept_material_tint(event)and #resumed==0,'foreign view reply cannot resume pending scene')
event.view=1;event.rows[1].key='wrong-state';check(not p.accept_material_tint(event),'reply must match requested state key')
event.rows[1].key=query.rows[1].key
check(p.accept_material_tint(event)and #resumed==2,'authenticated matching reply resumes both original scene identities')
local first=models.geometry('minecraft:oak_leaves','persistent=true',1,64,0)
local second=models.geometry('minecraft:oak_leaves','persistent=true',2,64,0)
check(first[1].tint_rgb==0x91bd59 and second[1].tint_rgb==0x6a7039,'same tint index consumes distinct queried biome RGB')
local ctx=object()
local value=handlers[1].resolve(ctx,first[1],asset_root)
check(value.material and #bakes==1 and bakes[1].rgb==0x91bd59,'actual material provider consumes the reply into baked pixels')
check(bakes[1].input=='material-pixels-v1/fixture/textures/minecraft/block/oak_leaves.png.rgba','selected model root uses actual private pixel namespace')
handlers[1].resolve(ctx,first[1],asset_root)
check(mids==2 and #imports==1,'existing per-profile MID and imported tinted texture reused')
-- One waterlogged coordinate can carry both leaf color and water color at index0.
blocks[position(3,64,0)]={id='minecraft:oak_leaves',state='waterlogged=true',properties={waterlogged='true'}}
local mixed={original,{texture='minecraft:block/water_still',alpha_mode='translucent',tint=0,tint_role='water'}}
local block={id='minecraft:oak_leaves',state='waterlogged=true',dim=scope.dim,x=3,y=64,z=0,properties={waterlogged='true'}}
wiring.driver:prepare('same-waterlogged-scene',block,mixed);p.tick(.05,.1);commands.tick()
local water_query=read(tmp..'/command.json');os.remove(tmp..'/command.json')
check(#water_query.rows==2,'water and block roles query separately at the same coordinate')
local colors={};for i,row in ipairs(water_query.rows)do colors[i]=row.tint_role=='water'and 0x3f76e4 or 0x91bd59 end
check(p.accept_material_tint(reply(water_query,colors)),'both actual color sources accepted')
local colored=wiring.driver:prepare('same-waterlogged-scene',block,mixed)
check(colored[1].tint_rgb==0x91bd59 and colored[2].tint_rgb==0x3f76e4,'waterlogged leaf never overwrites foliage with water blue')
-- Same block id, new properties/state: no old redstone/stem/leaf color reuse.
blocks[position(1,64,0)].state='persistent=false'
local changed=models.geometry('minecraft:oak_leaves','persistent=false',1,64,0)
check(changed[1].material_pending and not changed[1].tint_rgb,'new block state invalidates color cache')
p.tick(.05,.2);commands.tick();local old_query=read(tmp..'/command.json');os.remove(tmp..'/command.json')
local before=#resumed;scope.view=2;p.bind_material_scope(scope)
check(not p.accept_material_tint(reply(old_query,{0x123456}))and #resumed==before+1,'rebind rejects old reply and invalidates pending same scene once')
-- Bounded batching on the existing queue, including timeout/backoff attempts.
for x=10,42 do blocks[position(x,64,0)]={id='minecraft:oak_leaves',state='new'};models.geometry('minecraft:oak_leaves','new',x,64,0)end
p.tick(.05,.3);commands.tick();local batch=read(tmp..'/command.json');os.remove(tmp..'/command.json')
check(#batch.rows==32,'one existing tick emits at most32 small tint rows')
p.tick(.05,.4);commands.tick();local remainder=read(tmp..'/command.json');os.remove(tmp..'/command.json')
check(#remainder.rows<=2,'next tick sends only remaining unsent scenes')
check(ticks==5,'decorator calls only the original companion pipeline tick')
check(wiring.stop()and models.geometry==raw_geometry and #handlers==0 and p.material_runtime==nil,'normal stop restores geometry and removes owned handler')
check(not p.material_runtime,'no separate service/socket/timer constructed')
-- Execute the proposed real client_world factory, including waiting-ACK scope
-- binding before chunk readiness. This is still a fixture, never engine proof.
local Factory=dofile(tmp..'/factory/client_options.lua')
local origin={X=0,Y=0,Z=0,y_origin=64}
c.running=true;c.models=models;c.visual_pipeline=p;c.origin=origin;c.world.session=scope.world_session;c.world.committed_snapshots={}
local pawn=object({CapsuleComponent={GetScaledCapsuleHalfHeight=function()return 100 end}})
function pawn:K2_GetActorLocation()return{X=0,Y=0,Z=100}end
local ctx={collisions=c,pc={Pawn=pawn}}
local v={player=scope.mc_uuid,world_session=scope.world_session,dim=scope.dim,view=scope.view,waiting_ack=true}
local features={bootstrap_view=function()return v end}
local opts=Factory.new{json=J,bridge_root=tmp..'/',scripts_dir=base..'/palcraft/client/',origin=origin,
 config={identity={}},view_bridge={},travel_dir=base..'/palcraft/travel/',material_options=material_options,game_thread=function()return true end}
local worker=opts.client_world.new(ctx,features);worker:tick(0,ctx)
check(p.material_runtime and p.material_runtime.driver.scope.view==v.view,'actual client_world factory constructed consumer and bound current prepare view')
models.geometry('minecraft:oak_leaves','persistent=false',1,64,0);p.tick(.05,1);opts.command_bus.tick()
local factory_query=read(tmp..'/command.json');os.remove(tmp..'/command.json')
check(factory_query.mc_uuid==v.player and factory_query.view==v.view,'real factory current scope reached existing native command slot')
check(p.accept_material_tint(reply(factory_query,{0x456789})),'same original pipeline accepted factory query reply')
check(worker:stop('fixture_stop',ctx)and not p.material_runtime and models.geometry==raw_geometry,'factory lifecycle detached its own material consumer')
-- The owner's actual scheduler hook dirties only renderer cache/revision. It
-- preserves the authoritative block and uses its existing queue/frame budget.
local Scheduler=dofile(base..'/material-pipeline/runtime-increment/proposals/client/chunk_scheduler.lua')
local s=Scheduler.new{geometry={geometry=function()return{}end},adapter={}}
local row={id='minecraft:oak_leaves',state='persistent=false',at={1,64,0},boxes={}}
s:apply_blocks(scope.dim,{row},{})
local ch=s:_chunk(scope.dim,1,64,0);local revision=ch.revision;local signature=s:get(scope.dim,1,64,0).signature
ch.error='material_pending';s.errors[ch.key]=ch.error
check(s:invalidate_material(scope.dim,row.at)and ch.revision==revision+1 and not ch.error,'actual existing scheduler retries the same material section')
check(s:get(scope.dim,1,64,0).signature==signature and s.stats.changes==1 and s.stats.native_calls==0,'material reply does not mutate world data or run a second renderer tick')
os.remove(tmp..'/index.json');os.remove(tmp..'/command.json.pending')
print(string.format('{"status":"passed","checks":%d,"real_command_queue":true,"engine_calls":0,"fixture_rgb_only":true}',count))
