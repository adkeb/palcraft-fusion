-- Same client Lua VM and the existing client timer own this composition.
local dir=assert(debug.getinfo(1,'S').source:match('^@(.*[/\\])'))
local M={}
function M.new(o)
 local J,P=assert(o.json),assert(o.paths)
 local function read(p)local f=assert(io.open(p,'rb'));local v=J.decode(f:read('*a'));f:close();return v end
 local function write(p,v)local f=assert(io.open(p..'.tmp','wb'));f:write(J.encode(v));f:close();os.remove(p);assert(os.rename(p..'.tmp',p))end
 local scope=read(P.join('.palcraft/standalone/scope.json'))
 local permission=dofile(dir..'standalone_permissions.lua').new{json=J,paths=P,scope=scope}
 _G.PalCraftStandalonePermissions=permission
 local scripts=P.join('BridgeLab/Pal/Binaries/Win64/ue4ss/Mods/PalLiveBridge/Scripts')..'/'
 local R=dofile(scripts..'readers.lua')
 local realm=dofile(dir..'local_realm.lua').new{readers=R,game_thread=IsInGameThread,authorize_world_save=permission.authorize}
 local SP={scripts_dir=scripts,rpc_root=P.journal,bridge_root=P.bridge,local_realm=realm,
  client_control=assert(o.client_control,'Existing client lifecycle controls required'),
  game_thread=IsInGameThread,external_tick=true,scope=scope,
  client_worker=function()
   local f=o.client_features();local w=f and f.composition.features.client_world
   return w and w.instance
  end}
 function SP.start_early_boot(_,json,readers)
  local s={mode='standalone',world_directory=scope.world_directory,pal_uid=scope.pal_uid,
   scripts_dir=scripts,rpc_root=scope.rpc_root_windows,exchange_root=scope.exchange_root_windows}
  local service=dofile(scripts..'standalone_service.lua').new{scope=s,json=json,readers=readers,
   durable_dll=scope.durable_dll_windows,credit_dll=scope.credit_dll_windows}
  local helper=dofile(scripts..'escrow_setup.lua').new{authority_mode='standalone',world_directory=s.world_directory,
   scripts_dir=scripts,root=s.exchange_root,json=J,readers=readers,durable_dll=scope.durable_dll_windows,allow_build=true}
  _G.PalCraftStandaloneEscrowSetup=helper
  local observer={service=service}
  function observer.tick()
   local proof,why=realm:current();assert(proof,why)
   assert(realm:validate(proof,proof.pc)==true,'Actual standalone process context changed')
   service.tick()
  end
  function observer.ready()return service.ready==true end
  function observer.status()return{ready=service.ready==true,mode='standalone',actual_process_bound=service.ready==true,
   phase=service.ready and'actual_client_process_bound'or'normal_owned_load_pending',native_credit_runtime_verified=false}end
  function observer.stop()service.ready=false end
  return observer
 end
 assert(not rawget(_G,'PalCraftStandaloneBootstrap'),'Standalone dispatcher already installed in this VM')
 _G.PalCraftStandaloneBootstrap=SP
 local dispatcher=assert(dofile(scripts..'main.lua'))
 assert(type(dispatcher.tick)=='function','Standalone dispatcher must use the existing client timer')
 local api={realm=realm,permission=permission};local last_tick,last_status,last_sid
 function api:tick(ms)
  if last_tick and ms>=last_tick and ms-last_tick<250 then return end;last_tick=ms
  local proof,why=realm:current()
  if proof and proof.server_session_id~=last_sid then
   last_sid=proof.server_session_id
   write(P.bridge..'lab-identity.json',{realm_mode='standalone',world_directory=proof.world_id,
    server_session_id=proof.server_session_id,host_uid=proof.host_uid,process_epoch=proof.process_epoch,observed_unix=os.time()})
  end
  -- Native world loading or an unavailable owned save is a failed gate for
  -- this callback, not a permanent failure of each existing native worker.
  local ok,e
  if proof then ok,e=pcall(dispatcher.tick,ms)
  else ok,e=false,why or'Actual Standalone local realm unavailable'end
  if not last_status or ms<last_status or ms-last_status>=1000 then
   last_status=ms
   write(P.bridge..'standalone-runtime-status.json',{mode='standalone',authority=proof~=nil,
    server_session_id=proof and proof.server_session_id,world_id=proof and proof.world_id,host_uid=proof and proof.host_uid,
    reason=why,dispatcher_ok=ok,dispatcher_error=not ok and tostring(e)or nil,same_client_Lua_VM=true,
    existing_client_timer=true,observed_unix=os.time(),game_ready=false})
  end
 end
 return api
end
return M
