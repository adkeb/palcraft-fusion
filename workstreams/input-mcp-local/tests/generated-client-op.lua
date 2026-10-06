assert(IsInGameThread(),'Normal MC command requires game thread')
local request_json=[====[{"digest":"d","id":"a9dd3941-bf8b-4695-90ec-99a0f3c743d","query":{"duration_ms":20,"key":"use","method":"action"},"scope":{},"windows_root":"Z:/Fixture Owned Root"}]====]
local root=assert(os.getenv('PALCRAFT_WINDOWS_ROOT')):gsub('\\','/'):gsub('/+$','')
local J=dofile(root..'/PalCraft-Client/Pal/Binaries/Win64/ue4ss/Mods/PalCraftClient/Scripts/json.lua')
local q=J.decode(request_json);assert(root==q.windows_root,'Configured owned root changed')
local function read(name)local f=assert(io.open(root..'/PalCraft-Dev/bridge/'..name,'rb'));local v=J.decode(f:read('*a'));f:close();return v end
local function current()
 local host=read('session-bind-status.json');local boot=read('mc-bootstrap-status.json');local n=boot.native_binding
 assert(host.authenticated_host==true and boot.native_mc_verified==true and n.v==2 and n.legacy==false,'Actual native binding missing')
 assert(host.expires_at>os.time()and os.time()-host.updated_unix<=5 and os.time()-boot.updated_unix<=5,'Runtime binding stale')
 assert(host.session_id==q.scope.host_session_id and host.generation==q.scope.host_generation and host.server_session_id==q.scope.server_session_id,'HOST scope changed')
 assert(boot.host_scope.session_id==host.session_id and boot.host_scope.generation==host.generation,'Bootstrap HOST lease changed')
 assert(n.session_id==q.scope.mc_session_id and n.generation==q.scope.mc_generation and n.mc_epoch==q.scope.mc_epoch and n.expires_at>os.time(),'Native MC epoch changed')
 for _,key in ipairs({'pal_uid','mc_uuid','mc_name','world_id'})do assert(host.identity[key]==q.scope.identity[key],'Player identity changed')end
 for _,key in ipairs({'pal_uid','mc_uuid','world_id'})do assert(n[key]==q.scope.identity[key],'Native player identity changed')end
 assert(boot.world_view.world_session==q.scope.world_session and boot.world_view.dim==q.scope.dim,'World scope changed')
 return true
end
current()
local features=assert(_G.PalCraftClientFeatures);local command=assert(features.composition.features.commands)
assert(command.phase=='running'and command.instance,'Normal command bus unavailable')
local binding=assert(features.binding,'Live configured player binding missing')
assert(binding.session_id==q.scope.host_session_id and binding.generation==q.scope.host_generation and binding.expires_at>os.time(),'Live HOST binding changed')
if q.query.method=='action'or q.query.method=='slot'or q.query.method=='hud'then
 assert(not _G.PalCraftClientView.status().held,'World view held; normal input unavailable')
end
local file=root..'/PalCraft-Dev/bridge/mcp-normal-operations/'..q.id..'-dispatch.json'
local exists=io.open(file,'rb');if exists then local old=J.decode(exists:read('*a'));exists:close();assert(old.digest==q.digest,'Operation ID payload changed');return old end
local function save(value)local f=assert(io.open(file..'.pending','wb'));f:write(J.encode(value));f:close();os.remove(file);assert(os.rename(file..'.pending',file))end
local result={request_id=q.id,digest=q.digest,accepted=false,state='reserved',effect_confirmed=false}
save(result) -- Persist intent before touching the existing bus; ambiguity must not replay.
local method=q.query.method
local dispatched,dispatch_error=pcall(function()
if method=='action'then
 assert(command.instance.send{t='key',k=q.query.key,down=true,request_id=q.id}==true,'Normal command was not queued')
 result.accepted=true;result.state='submitted';save(result)
 ExecuteInGameThreadWithDelay(q.query.duration_ms,function()
  local ok,why=pcall(function()current();command.instance.send{t='key',k=q.query.key,down=false,request_id=q.id}end)
  result.state=ok and'submitted_release'or'unknown';result.error=not ok and tostring(why)or nil;save(result)
 end)
else
 local types={inspect='inspect',block='blockinspect',blocks='blocksync',slot='slot',hud='hud'}
 local row={t=assert(types[method]),request_id=q.id}
 if method=='block'then row.x=q.query.x;row.y=q.query.y;row.z=q.query.z
 elseif method=='blocks'then row.r=q.query.radius
 elseif method=='slot'then row.n=q.query.slot
 elseif method=='hud'then row.hidden=q.query.hidden end
 assert(command.instance.send(row)==true,'Normal command was not queued')
 result.accepted=true;result.state='submitted';save(result)
end
end)
if not dispatched then result.state='failed';result.error=tostring(dispatch_error);save(result)end
return result
