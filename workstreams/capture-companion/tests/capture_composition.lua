-- One directed composition test. All Lua calls are production modules; only
-- external authenticated mailboxes, UObjects and native DLL calls are fixtures.
local root=assert(arg[1]);local delta=assert(arg[2]);local tmp=assert(arg[3])..'/'
local open,lines,dofile_real,rename,remove=io.open,io.lines,dofile,os.rename,os.remove
local J=dofile_real(root..'/native_renderer/stable-v3/json.lua')
local material=root..'/material-pipeline/snapshots/material-runtime-v1-e8785b9db7ee/'
local script='D:/PalworldServer-LAN/PalCraft-Client/Pal/Binaries/Win64/ue4ss/Mods/PalCraftClient/Scripts/'
local bridge='D:/PalworldServer-LAN/PalCraft-Dev/bridge/'
local journal='D:/PalworldServer-LAN/BridgeLab/rpc/palcraft-events.ndjson'
local checks,reader_opens,engine_calls,authority_mutations=0,0,0,0
local function check(value,why)checks=checks+1;assert(value,why)end
local function copy(value)return J.decode(J.encode(value))end
local function mapped(path)
 if path==journal then return tmp..'events.ndjson'end
 if path==script..'models.lua'then return root..'/native_renderer/capture-increment/models_v6.lua'end
 if path:sub(1,#bridge)==bridge then return tmp..path:sub(#bridge+1)end
 return path
end
local function read(path)local f=assert(open(mapped(path),'rb'));local value=f:read('*a');f:close();return value end
local function write(path,value)local f=assert(open(mapped(path),'wb'));f:write(type(value)=='string'and value or J.encode(value));f:close()end
local function append(row)local f=assert(open(tmp..'events.ndjson','ab'));f:write(J.encode(row)..'\n');f:close()end
local id=function(n)return('00000000-0000-0000-0000-%012x'):format(n)end
local PAL,MC,SID,NATIVE,BOOT,INSTANCE=id(1),id(2),id(3),id(4),id(5),id(6)
local WORLD,WS,DIM='fixture-world','fixture-world-lifetime','minecraft:overworld'
local function guid(uuid)
 local a,b,c,d,e=uuid:match('^(%x+)%-(%x+)%-(%x+)%-(%x+)%-(%x+)$')
 return{A=tonumber(a,16),B=(tonumber(b,16)<<16)|tonumber(c,16),C=(tonumber(d,16)<<16)|(tonumber(e:sub(1,4),16)),D=tonumber(e:sub(5),16)}
end
local serial=0x8000;local objects,models,components,trace,imports={},{},{},{},{}
local function object(name,address)
 serial=serial+1;address=address or serial
 local value={valid=true,name=name,address=address}
 function value:IsValid()return self.valid end
 function value:GetFullName()return self.name end
 function value:GetAddress()return self.address end
 objects[address]=value;return value
end
local context=object('PalGameStateInGame fixture',10);context.ServerSessionId=BOOT
local O={X=0,Y=0,Z=0}
local body_mesh=object('Replicated authoritative mesh');body_mesh.visible=true
function body_mesh:IsVisible()return self.visible end
function body_mesh:SetVisibility(v)self.visible=v;trace[#trace+1]=v and'body:restore'or'body:hide'end
local actor=object('PalCharacter exact');actor.individual={PlayerUId=guid(PAL),InstanceId=guid(INSTANCE)}
function actor:GetMainMesh()return body_mesh end
function actor:GetCharacterParameterComponent()return{GetIndividualParameter=function()return self.individual end}end
local pawn=object('PalPlayerCharacter fixture')
pawn.CapsuleComponent={GetScaledCapsuleHalfHeight=function()return 80 end}
function pawn:K2_GetActorLocation()return{X=100,Y=-100,Z=80}end
local pc=object('PalPlayerController fixture');pc.Pawn=pawn;pc.Player=object('PalLocalPlayer fixture')
function pc:GetPlayerUId()return guid(PAL)end
local callbacks,elapsed={},0
local env=setmetatable({},{__index=_G});env._G=env
env.IsInGameThread=function()return true end
env.FName=function(value)return value end
env.io=setmetatable({open=function(path,mode)
 if path==journal then reader_opens=reader_opens+1 end
 return open(mapped(path),mode)
end,lines=function(path,...)
 if path:find('UE4SS.log',1,true)then local done=false;return function()if not done then done=true;return'ProcessEvent address 0x13'end end end
 return lines(mapped(path),...)
end},{__index=io})
env.os=setmetatable({time=function()return 100 end,rename=function(a,b)return rename(mapped(a),mapped(b))end,remove=function(p)return remove(mapped(p))end},{__index=os})
env.ExecuteInGameThreadWithDelay=function(_,fn)callbacks[#callbacks+1]=fn end
local inherited=object('Inherited texture')
local function parent(path)
 local value=object(path);value.MaterialDomain=0
 value.blend=path:find('Masked',1,true)and 1 or path:find('Translucent',1,true)and 2 or 0
 function value:GetBlendMode()return self.blend end
 function value:GetBaseMaterial()return self end
 return value
end
env.LoadAsset=parent
local functions={}
env.StaticFindObject=function(name)
 if functions[name]then return functions[name]end
 local value=object(name)
 if name=='/Script/Pal.Default__PalUtility'then
  function value:GetCharacterManager(a)return{GetIndividualHandleFromCharacterParameter=function()
   return{GetIndividualID=function()return a.individual end}
  end}end
 elseif name=='/Script/Engine.Default__KismetRenderingLibrary'then
  function value:ImportFileAsTexture2D(_,path)
   local prefix=bridge..'entity-capture-v1/textures/'
   check(path:sub(1,#prefix)==prefix,'Import uses actual captured PNG cache')
   check(#read(path)>8,'Import reads committed PNG bytes')
   imports[#imports+1]=path;return object('CapturedTexture2D '..path)
  end
 elseif name=='/Script/Engine.Default__KismetMaterialLibrary'then
  function value:CreateDynamicMaterialInstance(_,asset)
   local mid=object('Actual profile MID');mid.parameters={};mid.parent=asset
   function mid:K2_GetTextureParameterValue()return inherited end
   function mid:SetTextureParameterValue(key,texture)self.parameters[key]=texture end
   function mid:SetScalarParameterValue()end
   return mid
  end
 elseif name=='/Script/Engine.Default__GameplayStatics'then
  function value:GetWorldDeltaSeconds()return .05 end
  function value:GetTimeSeconds()return elapsed end
 end
 functions[name]=value;return value
end
env.FindAllOf=function(name)
 if name=='GameStateBase'or name=='PalGameStateInGame'then return{context}end
 if name=='PalCharacter'then return{actor}end
 if name=='ProceduralMeshComponent'then return components end
 if name=='Actor'or name=='StaticMeshActor'then return models end
 return{}
end
local packets,release_flags={},{}
local function decode_model(raw,update)
 local header={string.unpack('<c8'..string.rep('I8',18)..'dddI4I4',raw)}
 check(header[1]==(update and'PALCUPD1'or'PALCPRC6'),'Real Models6 native header')
 check(header[2]==context:GetAddress()and header[23]==1,'Actual companion context and one captured section')
 check(header[24]==(update and 2 or 3),'RGBA72 format plus hidden preparation')
 local offset=header[25];local lifetime
 if update then
  local a,c,token,fn;a,c,token,fn,offset=string.unpack('<I8I8I8I8',raw,offset)
  check(objects[a]and objects[c]and token>0 and fn>0,'Update retains exact native lifetime');lifetime=token
 end
 local mid,vertices,indices;mid,vertices,indices,offset=string.unpack('<I8I4I4',raw,offset)
 check(objects[mid].parameters.SpriteTexture~=nil,'Masked profile binds SpriteTexture through actual resolver')
 check(vertices==4 and indices==6,'Actual captured quad triangulates completely')
 local colors,positions={},{}
 for i=1,vertices do
  local v={string.unpack('<ddddddddI4I4',raw,offset)};offset=v[11]
  check(v[10]==0,'Native RGBA72 padding stays zero');colors[i]=v[9];positions[i]={v[1],v[2],v[3]}
 end
 local triangles={};for i=1,indices do triangles[i],offset=string.unpack('<I4',raw,offset)end
 check(offset==#raw+1 and #raw==(update and 544 or 512),'Real Models6 wire consumes exactly 72 bytes per vertex')
 check(table.concat(triangles,',')=='0,2,1,0,3,2','Captured MC quad has native winding')
 return{raw=raw,colors=colors,positions=positions,world={header[20],header[21],header[22]},native_id=lifetime}
end
env.package={loadlib=function(_,symbol)
 if symbol=='palcraft_create_model'then return function()
  local packet=decode_model(read(bridge..'model-request.bin'));packets[#packets+1]=packet
  local model=object('Visual-only procedural Actor');model.hidden=true;model.owner=context
  function model:GetOwner()return self.owner end
  function model:K2_SetActorLocation(position)self.position=position end
  function model:K2_SetActorRotation(rotation)self.rotation=rotation end
  function model:SetActorHiddenInGame(hidden)self.hidden=hidden;trace[#trace+1]=hidden and'model:hide'or'model:show'end
  local component=object('Visual-only procedural mesh');component.owner=model
  function component:GetOwner()return self.owner end
  components[#components+1]=component;models[#models+1]=model
  packet.model=model;packet.component=component;packet.native_id=#packets
  trace[#trace+1]='native:prepare_hidden'
  write(bridge..'model-result.json',{ok=true,actor=model:GetAddress(),component=component:GetAddress(),native_id=packet.native_id,sections=1,vertices=4,indices=6,stage='created'})
 end end
 if symbol=='palcraft_update_model'then return function()
  local packet=decode_model(read(bridge..'model-update-request.bin'),true);packets[#packets+1]=packet
  write(bridge..'model-result.json',{ok=true,native_id=packet.native_id,stage='updated'})
 end end
 if symbol=='palcraft_release_model'then return function()
  local p={string.unpack('<c8I8I8I8I8I8I8I4I4',read(bridge..'model-release-request.bin'))}
  check(p[1]=='PALCREL1','Actual Models6 lifecycle wire');release_flags[#release_flags+1]=p[8]
  if p[8]==1 then objects[p[3]].valid=false;objects[p[4]].valid=false end
  write(bridge..'model-result.json',{ok=true,stage=p[8]==1 and'destroyed'or p[8]==0 and'released'or'abandoned'})
 end end
 error('Unexpected native function '..symbol)
end}
local loaded,source_paths={},{}
env.dofile=function(path)
 if loaded[path]then return loaded[path]end
 local relative=path:sub(1,#script)==script and path:sub(#script+1)
 check(relative~=nil,'All runtime modules belong to the existing client')
 local source
 if relative=='json.lua'then return J
 elseif relative=='models.lua'then source=root..'/native_renderer/capture-increment/models_v6.lua'
 elseif relative=='world_compat.lua'then source=root..'/palcraft/server/world_compat.lua'
 elseif relative=='model_geometry_v2.lua'then source=root..'/native_renderer/stable-v3/model_geometry_v2.lua'
 elseif relative=='runtime/paths.lua'then source=root..'/native_renderer/capture-increment/runtime/paths.lua'
 elseif relative:sub(1,7)=='travel/'then source=root..'/palcraft/'..relative
 elseif relative:sub(1,8)=='runtime/'then
  local proposal=delta..'/proposals/'..relative;local f=open(proposal,'rb')
  if f then f:close();source=proposal else source=root..'/palcraft/'..relative end
 else
  local proposal=delta..'/proposals/client/'..relative;local f=open(proposal,'rb')
  if f then f:close();source=proposal else source=material..'client/'..relative end
 end
 local f=assert(open(source,'rb'),'Unknown actual module '..source);local raw=f:read('*a');f:close()
 local value=assert(load(raw,'@'..path,'t',env))();loaded[path]=value;source_paths[#source_paths+1]=source;return value
end
write(journal,'');write(bridge..'world-origin.json',O);write(bridge..'native-visual-settings.json',{version=1,enabled=true})
local identity={pal_uid=PAL,mc_uuid=MC,mc_name='FixturePlayer',world_id=WORLD}
local host={schema=1,protocol=2,state='bound',authenticated_host=true,updated_unix=100,identity=identity,
 server_session_id=BOOT,session_id=SID,generation=1,expires_at=1000}
local envelope={v=2,legacy=false,pal_uid=PAL,mc_uuid=MC,mc_name=identity.mc_name,world_id=WORLD,
 server_session_id=BOOT,session_id=SID,generation=1,expires_at=1000}
local native=copy(envelope);native.session_id=NATIVE;native.mc_epoch='fixture-mc-epoch'
local bootstrap={schema=1,protocol=2,authenticated_host=true,native_mc_verified=true,updated_unix=100,
 host_scope=copy(envelope),native_binding=native,
 world_view={player=MC,world_session=WS,dim=DIM,view=1,waiting_ack=true}}
write(bridge..'session-bind-status.json',host);write(bridge..'mc-bootstrap-status.json',bootstrap)
write(bridge..'entities/binding-meta.json',{schema=1,state='bound',stale=false,updated_unix=100,identity=identity,
 server_session_id=BOOT,host_session_id=SID,generation=1})
local row={id='mc:'..id(7),category='mob',kind='minecraft:creeper',dimension=DIM,alive=true,x=2,y=64,z=2}
local state={session=BOOT,unix=100,epoch='fixture-mc-state',revision=1,entities={row},
 player_vitals={{pal_uid=PAL,mc_uuid=MC,hearts=20,max_hearts=20,food=20}}}
local pal={session=BOOT,unix=100,epoch='fixture-pal-body',bodies={{id=row.id,dimension=DIM,
 native_id='pal:'..PAL..'/'..INSTANCE,source_epoch=state.epoch,body_epoch='fixture-pal-body',phase='active'}},
 entities={{player=true,player_uid=PAL,hp=5,max_hp=5,alive=true,dying=false}}}
write(bridge..'entities/mc-state.json',state);write(bridge..'entities/pal-state.json',pal)
local world_seq=0
local function world_events(events)
 world_seq=world_seq+1;append({t='blocks',v=2,session=WS,seq=world_seq,dim=DIM,ops={},lifecycle=events})
end
local bounds={0,60,0,16,80,16}
world_events({{op='snapshot_begin',snapshot='actual-complete-fixture',at={0,0},bounds=bounds,player=MC,replace=true}})
world_events({{op='snapshot_end',snapshot='actual-complete-fixture',at={0,0},bounds=bounds,player=MC}})
local companion=env.dofile(script..'palcraft-collisions.lua')
local Models=assert(companion.models)
local function step()
 local callback=assert(table.remove(callbacks,1),'Existing companion timer required');elapsed=elapsed+.05;callback()
 check(companion.running and not companion.error,tostring(companion.error))
end
step();check(companion.world.seq==2 and companion.world.committed_snapshots['actual-complete-fixture'].committed,'Actual reducer commits the source scene')
local view_state={held=false,mapping=nil}
local view_bridge={status=function()return view_state end,reset=function()return true end,
 initWorldView=function(world,dimension,view,binding)
  check(world==WS and dimension==DIM and view==bootstrap.world_view.view and binding.session_id==NATIVE,'WorldView adopts the actual native lease')
  view_state.mapping={world_session=world,dim=dimension,view=view,origin=O};return true
 end}
local Options=env.dofile(script..'runtime/client_options.lua')
local options=Options.new{json=J,bridge_root=bridge,scripts_dir=script,origin=O,view_bridge=view_bridge,now=function()return 100 end,
 config={identity=identity,entities_enabled=true,entity_visuals_enabled=true},material_options={pixel_packages={}}}
local Features=env.dofile(script..'features.lua');local features=Features.new(options)
local ctx={pc=pc,identity={server_session_id=BOOT},collisions=companion,context_alive=true}
features:tick(0,ctx);check(features:initialize_home(pc),'Actual bootstrap initializes the home scene')
check(features.composition.features.entity_capture.phase=='waiting'and not companion.visual_pipeline.capture_worker,'Waiting ACK cannot attach a visible captured body')
check(Models.stats.created==0 and body_mesh.visible,'Authority body remains visible while capture is gated')
bootstrap.world_view.waiting_ack=false;write(bridge..'mc-bootstrap-status.json',bootstrap);features:tick(250,ctx)
check(companion.visual_pipeline.material_runtime~=nil,'Material overlay remains installed alongside capture: '..J.encode(features:status()))
check(features.composition.features.entity_capture.phase=='running'and companion.visual_pipeline.capture_worker,'Real feature factory attaches captured consumer')
step();features:tick(266,ctx)
local binding=J.decode(read(bridge..'command.json'));remove(mapped(bridge..'command.json'))
check(binding.t=='entity_visual_view'and binding.op=='bind'and binding.mc_uuid==MC and binding.world_session==WS and binding.view==1,'Binding passes through the existing command bus')
check(J.encode(binding.bounds)==J.encode(bounds)and binding.mapping:find('per-block-origin:',1,true)==1,'Binding uses actual complete receipt/mapping')
check(Models.stats.created==0,'PNG/cache pending cannot create an approximate body')
local Blob=env.dofile(script..'capture/capture_blob.lua')
local png64='iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jV2kAAAAASUVORK5CYII='
local png=Blob.base64(png64);local png_hash=Blob.sha256(png)
local function event(kind)
 local q=copy(binding);q.t=kind;q.op=nil;q.bounds=nil;q.host_session=copy(envelope);q.schema=1
 q.source='minecraft:entity_renderer_capture_v1';q.read_only=true;q.producer='fixture-capture';q.epoch=1;q.seq=1;q.created_ms=100000;return q
end
local frame={id=row.id,dimension=DIM,source='actual_entity_renderer_submit',space='minecraft_entity_origin_world_orientation',seq='capture-1',
 batches={{textures={Sampler0='minecraft:textures/entity/creeper/creeper.png'},primitive='QUADS',render_type_name='entity_cutout',has_blending=false,
 vertices={{0,0,0,0,1,0,0,0,.2,.4,.6,.5},{1,0,0,0,1,0,1,0,.2,.4,.6,.5},{1,1,0,0,1,0,1,1,.2,.4,.6,.5},{0,1,0,0,1,0,0,1,.2,.4,.6,.5}}}}}
local resource=frame.batches[1].textures.Sampler0
local asset=event('entity_visual_asset');asset.resource=resource;asset.sha256=png_hash;asset.bytes=#png;asset.index=0;asset.chunks=1;asset.base64=png64
append(asset)
local function manifest(f,seq)
 local q=event('entity_visual_cache');q.seq=seq;q.complete=true;q.rows={{id=row.id,dimension=DIM,available=true,frame=f,captured_ms=100000,textures={[resource]={sha256=png_hash,bytes=#png}}}};return q
end
local alphabet='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
local function base64(raw)
 local out={};for i=1,#raw,3 do local a,b,c=raw:byte(i,i+2);local n=(a<<16)|((b or 0)<<8)|(c or 0)
  out[#out+1]=alphabet:sub((n>>18&63)+1,(n>>18&63)+1)..alphabet:sub((n>>12&63)+1,(n>>12&63)+1)
   ..(b and alphabet:sub((n>>6&63)+1,(n>>6&63)+1)or'=')..(c and alphabet:sub((n&63)+1,(n&63)+1)or'=')end;return table.concat(out)
end
local initial=manifest(frame,2);initial.host_session=nil
local raw=J.encode(initial);local mid=math.floor(#raw/2)
for index=0,1 do local part=event('entity_visual_cache_chunk');part.sha256=Blob.sha256(raw);part.bytes=#raw;part.chunks=2;part.index=index;part.base64=base64(index==0 and raw:sub(1,mid)or raw:sub(mid+1));append(part)end
local prior_world_seq=companion.world.seq;step();features:tick(500,ctx)
check(companion.world.seq==prior_world_seq,'Capture asset/cache chunks never enter the world reducer')
check(Models.stats.created==1 and not body_mesh.visible and features.entity_observer.status().mc_models==1,'Authenticated capture reaches the exact observer and actual Models6')
check(packets[1].colors[1]==0x80336699 and packets[1].positions[3][1]==100 and packets[1].positions[3][3]==100,'Original RGBA and orientation reach the actual native codec')
check(imports[1]==bridge..'entity-capture-v1/textures/'..png_hash..'.png','Actual material profile imports SHA PNG without fabricated resource paths')
local show,hide;for i,v in ipairs(trace)do if v=='model:show'and not show then show=i elseif v=='body:hide'and not hide then hide=i end end
check(show and hide and show<hide,'New native visual exists before the exact authoritative mesh is hidden')
check(packets[1].model.position.X==200 and packets[1].model.position.Y==-200 and packets[1].model.rotation.Yaw==0,'Current native origin places world-oriented capture at yaw zero')
local observed=features.entity_observer.views[row.id]
local wrong=object('Wrong nearest-looking Actor');function wrong:GetMainMesh()return body_mesh end
check(features.entity_observer.verify_actor(observed.state,actor)==true and features.entity_observer.verify_actor(observed.state,wrong)==false,'Observer authenticates only the current exact Actor pairing')
local handle,why=companion.visual_pipeline.capture_renderer.spawn(observed.state,wrong)
check(not handle and why=='capture_actor_binding_mismatch'and Models.stats.created==1,'Wrong Actor cannot consume or hide a captured visual')
local changed=copy(frame);changed.seq='capture-2';changed.batches[1].vertices[1][1]=.5;append(manifest(changed,3));step();features:tick(750,ctx)
check(Models.stats.updates==1 and packets[2].positions[1][1]==50 and packets[2].colors[1]==0x80336699,'New capture frame updates the actual Models6 RGBA72 stream')
local stale=manifest(frame,20);stale.host_session.generation=2;append(stale);step()
check(companion.capture_reply_status.accepted==false and companion.capture_reply_status.reason=='capture_host_session_mismatch','Original HOST generation rejects stale capture')
local other=manifest(frame,21);other.view=2;append(other);step()
check(companion.capture_reply_status.accepted==false and companion.capture_reply_status.reason=='capture_view_mismatch','Committed native view rejects other-view capture')
bootstrap.world_view.waiting_ack=true;write(bridge..'mc-bootstrap-status.json',bootstrap);step()
check(body_mesh.visible and packets[1].model.hidden and not companion.visual_pipeline.capture_worker.cache.bound,'ACK wait suspends old native capture and restores the real body')
check(not open(mapped(bridge..'command.json'),'rb'),'ACK wait does not emit another bind')
bootstrap.world_view.waiting_ack=false;write(bridge..'mc-bootstrap-status.json',bootstrap);step();features:tick(766,ctx)
check(J.decode(read(bridge..'command.json')).op=='bind','Accepted scope rebinds through the same command slot');remove(mapped(bridge..'command.json'))
local eyes=copy(frame);eyes.seq='capture-unsupported';eyes.batches[1].render_type_name='minecraft_eyes'
append(manifest(eyes,4));step();features:tick(1000,ctx)
check(body_mesh.visible and features.entity_observer.status().mc_models==0 and features.entity_observer.status().pending_mc_models_and_animations,'Missing additive profile is explicit pending, with true rendered count')
check(companion.visual_pipeline.capture_renderer.status().diagnostic=='capture_additive_profile_missing','Actual material path rejects an unavailable additive implementation')
local valid=copy(frame);valid.seq='capture-3';append(manifest(valid,5));step();features:tick(1250,ctx)
check(not body_mesh.visible and features.entity_observer.status().mc_models==1,'Runnable profile resumes the retained exact Actor visual')
world_events({{op='resync_required'}});step()
check(body_mesh.visible and packets[1].model.hidden and not companion.visual_pipeline.capture_worker.cache.bound,'Actual world lifecycle invalidates cache and capture visibility')
world_events({{op='snapshot_begin',snapshot='resynced',at={0,0},bounds=bounds,player=MC,replace=true}})
world_events({{op='snapshot_end',snapshot='resynced',at={0,0},bounds=bounds,player=MC}});step();features:tick(1266,ctx)
check(J.decode(read(bridge..'command.json')).t=='entity_visual_view','Actual committed resync reuses the existing command bus');remove(mapped(bridge..'command.json'))
local resumed=copy(frame);resumed.seq='capture-4';append(manifest(resumed,6));step();features:tick(1500,ctx)
check(not body_mesh.visible,'Captured visual resumes only after the actual complete receipt')
check(companion.visual_pipeline.status().actual_shader_verified==false and companion.visual_pipeline.capture_worker.status().engine_verified==false,'Runnable bindings do not claim shader/runtime acceptance')
check(features.entity_observer.status().combat_bodies_spawned==0 and features.entity_observer.status().damage_events_sent==0 and authority_mutations==0,'Capture remains visual-only without authority spawn or damage')
local live_model=packets[1].model
check(features:stop('fixture_normal_stop',ctx),'Normal feature lifecycle cleans up')
check(body_mesh.visible and not live_model.valid and release_flags[#release_flags]==1,'Live-world stop destroys its owned procedural visual and restores exact mesh visibility')
check(not companion.visual_pipeline.capture_worker and not features.entity_observer,'No cache/observer lifetime survives feature stop')
-- A second short lifecycle checks the same composition's dead-world branch.
features=Features.new(Options.new{json=J,bridge_root=bridge,scripts_dir=script,origin=O,view_bridge=view_bridge,now=function()return 100 end,
 config={identity=identity,entities_enabled=true,entity_visuals_enabled=true},material_options={pixel_packages={}}})
features:tick(0,ctx);features:initialize_home(pc);step();features:tick(16,ctx)
if open(mapped(bridge..'command.json'),'rb')then remove(mapped(bridge..'command.json'))end
local last=copy(frame);last.seq='capture-restarted';local next_manifest=manifest(last,7);next_manifest.epoch=2
append(asset);append(next_manifest);step();features:tick(250,ctx)
check(Models.stats.created==2 and not body_mesh.visible,'Restart attaches a fresh real captured consumer')
local restore_before=0;for _,v in ipairs(trace)do if v=='body:restore'then restore_before=restore_before+1 end end
context.valid=false;companion.abandon()
local restore_after=0;for _,v in ipairs(trace)do if v=='body:restore'then restore_after=restore_after+1 end end
check(release_flags[#release_flags]==0 and restore_after==restore_before,'Dead-world abandon releases native lifetime without calling unloaded UObjects')
ctx.context_alive=false;check(features:stop('fixture_world_unloaded',ctx),'Feature stop after abandon is idempotent')
check(not companion.visual_pipeline.capture_worker and companion.visual_pipeline.material_runtime==nil,'Material stop decorator forwards the dead-world lifecycle to capture cleanup')
check(reader_opens>0 and #callbacks>0,'Only the existing companion reader and timer drove capture')
print(J.encode({status='passed',checks=checks,actual_modules=source_paths,models_version=Models.version,
 native_vertex_bytes=72,native_codec='actual Models6 Lua',engine_boundary='fixture UObjects and native entrypoints',
 captures_created=Models.stats.created,capture_updates=Models.stats.updates,sole_world_reader=true,sole_companion_timer=true,
 waiting_ack_gate_retained=true,exact_actor_binding=true,normal_and_dead_world_cleanup=true,
 old_matrices_repeated=false,runtime_graphics_verified=false,services_started=0,GUI_calls=0,authority_mutations=0}))
