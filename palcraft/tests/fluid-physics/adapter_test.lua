-- Offline semantic tests. These are NOT evidence of live Pal swimming or damage.
local base=arg[1]or'work/minecraft-fusion/palcraft/'
local Core=dofile(base..'native/fluid_physics_core.lua')
local World=dofile(base..'server/world_compat.lua');local Driver=dofile(base..'server/world_fluid.lua')
local checks=0;local names={}
local function check(v,msg)checks=checks+1;assert(v,msg);names[#names+1]=msg end
local function close(a,b)return math.abs(a-b)<1e-7 end
local function actor(n)
 local m={GravityScale=1,WaterPlaneZ=-10000,WaterPlaneZPrev=-10000,InWaterRate=0,MovementMode=1,CustomMovementMode=0,
  calls={enter=0,exit=0,mode=0,impulse=0},velocity={X=0,Y=0,Z=0}}
 function m:IsValid()return true end;function m:IsA(path)return path=='/Script/Pal.PalCharacterMovementComponent'end
 function m:IsSwimming()return self.MovementMode==4 end
 function m:SetMovementMode(mode,custom)self.MovementMode=mode;self.CustomMovementMode=custom;self.calls.mode=self.calls.mode+1 end
 function m:OnEnterWater()self.entered=true;self.calls.enter=self.calls.enter+1 end
 function m:OnExitWater()self.entered=false;self.calls.exit=self.calls.exit+1 end
 function m:IsEnteredWater()return self.entered==true end
 function m:GetInWaterRate()return self.InWaterRate end
 function m:GetVelocity()return self.velocity end
 function m:GetGravityZ()return-980*self.GravityScale end
 function m:AddImpulse(v,b)assert(b==true);self.impulse=v;self.calls.impulse=self.calls.impulse+1 end
 local a={CharacterMovement=m};function a:IsValid()return self.valid~=false end
 function a:HasAuthority()return self.authority~=false end;function a:GetAddress()return n end
 a.CapsuleComponent={IsValid=function()return true end,GetScaledCapsuleHalfHeight=function()return 90 end,
  GetScaledCapsuleRadius=function()return 30 end,K2_GetComponentLocation=function()return a.position or{X=1050,Y=1950,Z=3090}end}
 function a:K2_GetActorLocation()return self.position or{X=1050,Y=1950,Z=3090}end
 return a
end
local native={commits=0,boxes={}}
function native:replace(context,origin,revision,boxes)self.commits=self.commits+1;self.boxes=boxes;self.origin=origin;self.revision=revision;return true end
function native:reset(alive)self.boxes={};self.resets=(self.resets or 0)+1;self.alive=alive end
function native:status()return{commits=self.commits,boxes=#self.boxes,collision=1}end
local world=World.new{dimension='minecraft:overworld'};local seq=0
local function block(at,kind,height,solid,flow,waterlogged)
 local boxes=solid or{}
 return{op='upsert',at=at,id='minecraft:'..(kind=='none'and'oak_planks'or kind),boxes=boxes,solid=#boxes>0,visible=true,
  fluid={kind=kind,height=height or 0,flow=flow or{0,0,0},waterlogged=waterlogged or false}}
end
local function ingest(ops,life,session)
 seq=seq+1;assert(world:ingest{t='blocks',v=2,session=session or'fluid_test',seq=seq,tick=seq,dim=world.dimension,ops=ops or{},lifecycle=life})
end
ingest{block({0,64,0},'water',8/9,nil,{1,0,.5}),block({2,64,0},'none',nil,{{0,0,0,1,1,1}}),
 block({4,64,0},'lava',8/9),block({6,64,0},'water',8/9,{{0,0,0,1,.5,1}},nil,true)}
ingest({},{{op='snapshot_begin',snapshot='committed_fixture',at={0,0},bounds={-16,60,-16,16,80,16},replace=false}})
ingest({},{{op='snapshot_end',snapshot='committed_fixture',at={0,0},bounds={-16,60,-16,16,80,16},replace=false}})
local A,B,context=actor(0x50100),actor(0x50200),actor(0x50300)
local participants={{id='player:a',actor=A,dim=world.dimension,feet={2.5,64,.5}},
 {id='pal:b',actor=B,dim=world.dimension,feet={.5,64,.5}}}
local options={side='server',world=world,origin={X=1000,Y=2000,Z=3000},contact_driver=Driver,
 native=native,game_thread=function()return true end,resolve_participants=function()return participants end,
 resolve_context=function()return context end,query_interval_ms=1}
local adapter=Core.new(options);check(adapter.ticks==0 and native.commits==0,'construction performs no engine work')
adapter:tick(1000,{})
check(A.CharacterMovement.calls.enter==0 and A.CharacterMovement.MovementMode==1,'ordinary MC wood never creates native water state')
check(B.CharacterMovement.calls.enter==1 and B.CharacterMovement.MovementMode==4,'one source block gives actual movement API calls for a Pal')
check(close(B.CharacterMovement.WaterPlaneZ,3000+(8/9)*100),'MC surface becomes the correct Pal water plane')
check(B.CharacterMovement.GravityScale==0 and B.CharacterMovement.InWaterRate>0,'surface buoyancy owns gravity only while swimming')
local commit=native.commits;adapter:tick(1050,{})
check(native.commits==commit,'unchanged fluid geometry retains native query bodies')
check(close(B.CharacterMovement.impulse.X,28)and close(B.CharacterMovement.impulse.Y,-14),'flow adds real velocity-change impulses with correct MC to Pal axes')
check(adapter.observations['pal:b'].sustained_swim_samples>0,'observations distinguish pre-apply swimming from the request')
ingest({},{{op='snapshot_begin',snapshot='in_progress',at={0,0},bounds={-16,60,-16,16,80,16},replace=false}})
local before_unknown=native.commits;adapter:tick(1070,{})
check(B.CharacterMovement.calls.exit==0 and B.CharacterMovement.GravityScale==0 and adapter.observations['pal:b'].known==false,'unknown body snapshot preserves physics rather than inventing a dry exit')
check(native.commits==before_unknown and adapter:status().query_snapshot_pending,'pending snapshot preserves the committed water-query batch')
ingest({},{{op='snapshot_end',snapshot='in_progress',at={0,0},bounds={-16,60,-16,16,80,16},replace=false}})
participants[1].feet={.5,64,.5};adapter:tick(1100,{})
check(A.CharacterMovement.MovementMode==4 and A.CharacterMovement.calls.enter==1,'the same contact adapter reaches the actual player actor')
participants[2].feet={2.5,64,.5};adapter:tick(1150,{})
check(B.CharacterMovement.MovementMode==3 and B.CharacterMovement.GravityScale==1 and B.CharacterMovement.calls.exit==1,'water exit restores gravity and delegates landing to native floor physics')
check(B.CharacterMovement.WaterPlaneZ==-10000 and B.CharacterMovement.InWaterRate==0,'water exit restores owned water fields')
participants[1].feet={4.5,64,.5};adapter:tick(1200,{})
check(adapter.contacts['player:a'].kind=='lava'and A.CharacterMovement.MovementMode~=4,'lava remains lava instead of a water or swimming volume')
check(adapter:status().lava_damage_calls==0,'no second lava damage timer or HP mutation exists')
local slab=Core.geometry(world:fluid_volumes(world.dimension,{6,64,0,7,65,1}))
check(#slab==1 and close(slab[1][3],6450)and close(slab[1][6],(64+8/9)*100),'waterlogged slab subtracts the actual solid volume')
local pool={};for z=0,3 do for x=0,3 do pool[#pool+1]={at={x,64,z},kind='water',height=8/9}end end
local merged,metadata=Core.geometry(pool)
check(#merged==1 and metadata.water_cells==16 and merged[1][1]==0 and merged[1][4]==400,'equal-height pool union is exact and uses one query box')
local low=Core.geometry{{at={0,64,0},kind='water',height=.2},{at={1,64,0},kind='water',height=.4}}
check(#low==2,'flowing levels are never inflated into full cube water')
local empty=Core.geometry{{at={0,64,0},kind='lava',height=1},{at={1,64,0},kind='none'}}
check(#empty==0,'lava and dry blocks create zero water query components')
local pillar=Core.geometry{{at={-1,64,-1},kind='water',height=1,waterlogged=true,solid_boxes={{.25,0,.25,.75,1,.75}}}}
local volume=0;for _,b in ipairs(pillar)do volume=volume+(b[4]-b[1])*(b[5]-b[2])*(b[6]-b[3])/1000000 end
check(close(volume,.75),'carved water query volume excludes the complete fence pillar')
local engine=Core.Engine.new(options);local p={actor=A,dim=world.dimension};A.position={X=1050,Y=1950,Z=3090}
local pose=engine:pose(p)
check(close(pose.feet[1],.5)and close(pose.feet[2],64)and close(pose.feet[3],.5)and close(pose.height,1.8),'physical capsule feet and dimensions convert correctly')
B.CharacterMovement.GravityScale=.75;adapter:remove('pal:b')
check(B.CharacterMovement.GravityScale==.75,'removing an already dry participant preserves subsequent native gravity changes')
participants={participants[1]};participants[1].feet={.5,64,.5};adapter:tick(1250,{})
local mode_calls=A.CharacterMovement.calls.mode;A.CharacterMovement.MovementMode=0;adapter:tick(1300,{})
check(A.CharacterMovement.MovementMode==0 and A.CharacterMovement.calls.mode==mode_calls,'disabled or dead movement is never re-enabled by water sampling')
A.CharacterMovement.MovementMode=1;adapter:tick(1350,{});adapter:stop('test_done',{context_alive=true})
check(A.CharacterMovement.GravityScale==1 and #native.boxes==0 and adapter.running==false,'stop removes query water and restores a wet participant')
local dryactor=actor(0x50400);dryactor.authority=false
local ok=pcall(engine.attach,engine,{actor=dryactor})
check(not ok,'server contact adapter rejects non-authoritative actors')
local nightactor=actor(0x50500);local night_options={};for k,v in pairs(options)do night_options[k]=v end
night_options.resolve_participants=function()return{{id='pal:night',actor=nightactor,dim=world.dimension,feet={.5,64,.5}}}end
local night=Core.new(night_options);night:tick(2000,{});night:tick(2133,{})
check(close(nightactor.CharacterMovement.impulse.X,74.48),'15FPS feature cadence preserves the full 133ms flow impulse')
night:stop('night_test_done',{context_alive=true})
ingest{block({8,64,0},'water',1),block({8,65,0},'water',1),block({8,66,0},'water',8/9)}
local deepactor=actor(0x50600);local deep_options={};for k,v in pairs(options)do deep_options[k]=v end
local deep_participant={id='pal:deep',actor=deepactor,dim=world.dimension,feet={8.5,64,.5}}
deep_options.resolve_participants=function()return{deep_participant}end
local deep=Core.new(deep_options);deep:tick(3000,{})
check(close(deepactor.CharacterMovement.WaterPlaneZ,3000+(2+8/9)*100)and deep.contacts['pal:deep'].surface_known,'deep-water buoyancy uses the connected column top rather than the body-cell top')
check(deepactor.CharacterMovement.InWaterRate==1 and deepactor.CharacterMovement.GravityScale==0,'known deep surface applies actual immersion and sampled buoyancy')
deep.driver.column.options.max_surface_cells=1;local old_plane=deepactor.CharacterMovement.WaterPlaneZ;deep:tick(3050,{})
check(deep.contacts['pal:deep'].known and not deep.contacts['pal:deep'].surface_known and deep.contacts['pal:deep'].surface==nil,'known wet body with an unknown surface does not invent a buoyancy plane')
check(deepactor.CharacterMovement.GravityScale==1 and deepactor.CharacterMovement.WaterPlaneZ==old_plane and deepactor.CharacterMovement.calls.impulse==0,'lost surface proof releases gravity override and applies zero fabricated buoyancy impulse')
check(deepactor.CharacterMovement.calls.exit==0 and deep:status().participants[1].observation.buoyancy_pending,'unknown surface preserves real wet contact and explicitly reports buoyancy pending')
deep:stop('deep_test_done',{context_alive=true})
local tall_blocks={};for y=64,76 do tall_blocks[#tall_blocks+1]=block({8,y,0},'water',1)end
tall_blocks[#tall_blocks+1]=block({8,77,0},'water',8/9);ingest(tall_blocks)
local tallactor=actor(0x50700);local tall_options={};for k,v in pairs(options)do tall_options[k]=v end
tall_options.resolve_participants=function()return{{id='pal:tall',actor=tallactor,dim=world.dimension,feet={8.5,64,.5}}}end
local tall=Core.new(tall_options);tall:tick(4000,{})
local highest=-math.huge;for _,b in ipairs(native.boxes)do highest=math.max(highest,b[6])end
check(close(highest,(77+8/9)*100),'native query window includes the proved deep surface without creating a truncated +8 top face')
local tall_commits=native.commits;tall.driver.column.options.max_surface_cells=1;tall:tick(4050,{})
check(native.commits==tall_commits and tall:status().query_surface_pending,'unknown surface never replaces the native batch with a fabricated local top')
tall:stop('tall_test_done',{context_alive=true})
local pointers={};for i=1,19 do pointers[i]=0x10000+i*0x100 end
local bytes=Core.encode(pointers,{1,2,3},9,7,0,merged)
check(#bytes==216+48,'Lua native water wire matches the independently asserted C++ ABI')
if arg[2]then local f=assert(io.open(arg[2],'wb'));f:write(bytes);f:close()end
print('{"ok":true,"suite":"fluid_adapter_semantics","checks":'..checks..',"live_swimming_verified":false,"live_damage_verified":false,"power_mode":"night_low_power"}')
