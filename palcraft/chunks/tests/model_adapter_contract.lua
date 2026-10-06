-- Execute the real renderer owner's Lua API. Only engine objects/spawn and the
-- DLL boundary are simulated; no graph, process, server, or RPC is started.
local T=dofile('/path/to/workspace/work/minecraft-fusion/palcraft/chunks/tests/support.lua')
local checks=0
local function check(v,message)checks=checks+1;assert(v,message)end
local work=T.root..'chunk_scaling/model-contract/'
local actors,serial={},0x50000
local env=setmetatable({}, {__index=_G});env._G=env
env.IsInGameThread=function()return true end
env.dofile=function(path)
 if path:match('json.lua$')then return T.J end
 if path:match('model_geometry_v%d.lua$')then return{configure=function()end}end
 error('Unexpected renderer module '..path)
end
env.FindAllOf=function(kind)local list={};for _,a in pairs(actors)do if a.alive then list[#list+1]=a end end;return list end
local source=assert(io.open(T.root..'palcraft/client/models.lua','rb'));local model_source=source:read('*a');source:close()
local Models=assert(load(model_source,'@'..T.root..'palcraft/client/models.lua','t',env))()
function Models.spawn_groups(ctx,origin,groups,at,options)
 check(options.hidden==true,'Real Model.prepare requests hidden engine spawn')
 serial=serial+0x100
 local a={address=serial,alive=true,hidden=true}
 function a:IsValid()return self.alive end
 function a:GetAddress()return self.address end
 function a:SetActorHiddenInGame(v)self.hidden=v end
 function a:K2_DestroyActor()self.alive=false end
 actors[a.address]=a;return a.address,a.address+0x40
end
local native_handles,native_serial,native_generation={},0x80000,1
local native_calls={}
local function native()
 local f=assert(io.open(work..'chunk-collision-request.bin','rb'));local bytes=f:read('*a');f:close()
 local x,y,z,revision,generation,action,boxes,newcount,oldcount=string.unpack('<dddI8I8I4I4I4I4',bytes,161)
 native_calls[#native_calls+1]=action
 local fresh,previous={},{ };local offset=217+boxes*48
 for _,item in ipairs({{fresh,newcount},{previous,oldcount}})do for _=1,item[2]do
  local actor,count,reserved,next_offset=string.unpack('<I8I4I4',bytes,offset);offset=next_offset;check(reserved==0,'Native handle padding')
  local h={actor=actor,components={}}
  for _=1,count do local value;value,offset=string.unpack('<I8',bytes,offset);h.components[#h.components+1]=value end
  item[1][#item[1]+1]=h
 end end
 local result={ok=true,version=1,actor='0x0',revision=revision,generation=generation,components={}}
 if action==3 then
  check(generation>native_generation,'Abandon increases native generation');native_generation=generation;native_handles={};result.stage='abandoned'
 else
  check(generation==native_generation,'Native generation synchronized')
  if action==0 then
   native_serial=native_serial+0x100;local h={actor=native_serial,components={},revision=revision,state='prepared'}
   for i=1,boxes do h.components[i]=native_serial+0x8000+i*8;result.components[i]=string.format('0x%x',h.components[i])end
   native_handles[h.actor]=h;result.actor=string.format('0x%x',h.actor);result.stage='prepared'
  else
   for _,h in ipairs(fresh)do
    local known=native_handles[h.actor];check(known and known.revision==revision and known.state=='prepared','Native fresh revision fence')
   end
   for _,h in ipairs(previous)do check(native_handles[h.actor]~=nil,'Native previous handle exists')end
   if action==1 then
    for _,h in ipairs(fresh)do native_handles[h.actor].state='active'end
    for _,h in ipairs(previous)do native_handles[h.actor]=nil end;result.stage='committed'
   elseif action==2 then for _,h in ipairs(previous)do native_handles[h.actor]=nil end;result.stage='unloaded'
   elseif action==4 then result.stage='preflight'else error('Unexpected native action')end
  end
 end
 f=assert(io.open(work..'chunk-collision-result.json','wb'));f:write(T.J.encode(result));f:close()
end
local C=dofile(T.root..'palcraft/client/chunk_collision.lua').new({json=T.J,root=work,process_event=0x22000,native=native,
 resolve_address=function(path)return 0x11000 end})
local A=dofile(T.root..'palcraft/client/chunk_adapter.lua').new({models=Models,collision=C,visual_verified=true,collision_verified=true})
local context={};function context:IsValid()return true end;function context:GetAddress()return 0x11000 end
local s=T.S.new({geometry=T.geometry,adapter=A,context=context,origin={X=120,Y=230,Z=340},session='real-model-contract',frame_budget_ms=2,frame_steps=64})
local groups=T.geometry.geometry('minecraft:oak_planks','',0,64,0)
check(not pcall(Models.prepare,context,{X=0,Y=0,Z=0},{groups=groups,at={0,64,0},revision=1}),'Real Model API rejects absent world/view fence')
s:apply_blocks(nil,{T.block(0,64,0)});T.drain(s)
local first;for _,ch in pairs(s.chunks)do first=ch end
check(first.packet.fence.world_session=='real-model-contract'and first.packet.fence.view==0,'Scheduler supplied actual renderer fence')
local vh,ch=first.active.visual[1],first.active.collision[1]
check(vh.state=='active'and ch.state=='active'and vh.native_registered and ch.native_registered,'Real Model and collider committed together')
check(vh.fence.mapping==ch.fence.mapping and not actors[vh.actor].hidden,'Matching native fence and visible model')
s:apply_blocks(nil,{T.block(0,64,0,'stone')});T.drain(s)
check(vh.state=='released'and ch.state=='released'and not actors[vh.actor].alive,'Real transaction retires old model/collider')
s:apply_blocks(nil,{},{{0,64,0}});T.drain(s)
check(#first.active.visual==0 and #first.active.collision==0,'Empty revision uses actual Model empty-new transaction')
s:apply_blocks(nil,{T.block(0,64,0)});T.drain(s);s:reconnect(true);T.drain(s)
check(Models.status().generation==2 and C.status().generation==2 and s.generation==2,'Reconnect synchronizes all real Lua adapters')
local server=T.S.new({geometry=T.geometry,adapter=A,context=context,origin={X=120,Y=230,Z=340},session='real-model-contract',visuals=false})
server.generation=2;server:apply_blocks(nil,{T.block(16,64,0)});T.drain(server)
local committed;for _,c in pairs(server.chunks)do committed=c end
check(#committed.active.visual==0 and #committed.active.collision==1,'Server collision-only path commits through actual renderer API')
server:unload('minecraft:overworld',1,4,0);T.drain(server)
local result={status='passed',checks=checks,renderer_api='actual palcraft/client/models.lua v4',native_boundary='simulated PALCCOL1 DLL',
 collision_runtime_verified=false,graphics_started=false,power_mode='night_low_power',native_calls=#native_calls}
T.write('model-adapter-contract.json',result);print(T.J.encode(result))
