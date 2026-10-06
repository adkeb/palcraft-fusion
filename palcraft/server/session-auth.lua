-- Pal authority presence for MC guest registration/login. Load only on the server game thread.
-- Uses the same HasAuthority/GetPlayerUId/IndividualHandle getters as the existing BridgeLab code.
-- No client-supplied UID becomes an identity; this module writes observed authoritative controllers only.
local M={}
function M.new(opts)
 opts=opts or{}
 local J=assert(opts.json,'json module required');local R=assert(opts.readers,'readers module required')
 local root=assert(opts.root,'server-owned auth directory required'):gsub('\\','/')
 if root:sub(-1)~='/'then root=root..'/'end
 local function live(o)return o and o:IsValid()and not o:GetFullName():find('Default__',1,true)end
 local function objects(c)local a={};for _,o in ipairs(FindAllOf(c)or{})do if live(o)then a[#a+1]=o end end;return a end
 local function guid(g)return R.guid_to_string({A=g.A,B=g.B,C=g.C,D=g.D}):lower()end
 local function text(v)return type(v)=='string'and v or v:ToString()end
 local function write(path,out)
  local tmp=path..'.tmp';local f=assert(io.open(tmp,'wb'));f:write(J.encode(out));f:close()
  -- UE4SS Lua has no replace-existing rename on Windows. Readers fail closed during this short gap.
  os.remove(path);assert(os.rename(tmp,path))
 end
 local api={};local last_write=0
 function api.snapshot()
  if opts.local_realm then
   local context,why=opts.local_realm:current();assert(context,why)
   assert(opts.local_realm:validate(context,context.pc)==true,'Standalone authority context changed')
   return{v=2,authority=true,realm_mode='standalone',net_mode=context.net_mode,
    world_id=context.world_id,server_session_id=context.server_session_id,updated_unix=os.time(),
    world_save_root=context.world_save_root,realm_generation=context.realm_generation,
    process_epoch=context.process_epoch,players=J.array{{pal_uid=context.host_uid,
     possessed=true,saved_account=true,local_controller=true,owned_transmitter=true}}}
  end
  local gs
  for _,o in ipairs(objects('PalGameStateInGame'))do if o:HasAuthority()then assert(not gs,'Multiple authoritative game states');gs=o end end
  assert(gs,'No authoritative Pal game state')
  local accounts={}
  for _,a in ipairs(objects('PalPlayerAccount'))do
   if live(a.IndividualHandle)then accounts[guid(a.IndividualHandle:GetIndividualID().PlayerUId)]=true end
  end
  local players=J.array();local seen={}
  for _,pc in ipairs(objects('PalPlayerController'))do
   if pc:HasAuthority()and live(pc.Pawn)then
    local uid=guid(pc:GetPlayerUId())
    if uid~='00000000-0000-0000-0000-000000000000'and accounts[uid]then
     assert(not seen[uid],'Duplicate authoritative Pal UID');seen[uid]=true
     players[#players+1]={pal_uid=uid,possessed=true,saved_account=true}
    end
   end
  end
  table.sort(players,function(a,b)return a.pal_uid<b.pal_uid end)
  return {v=2,authority=true,world_id=text(gs:GetWorldSaveDirectoryName()),server_session_id=text(gs.ServerSessionId),updated_unix=os.time(),players=players}
 end
 function api.tick()
  local now=os.time();if now==last_write then return end;last_write=now
  local ok,out=pcall(api.snapshot)
  if not ok then out={v=2,authority=false,updated_unix=now,players=J.array(),error=tostring(out)}end
  write(root..'pal-presence.json',out)
  return out
 end
 function api.resolve(mc_uuid,sessions)
  local p=api.snapshot();assert(type(sessions)=='table'and sessions.v==2,'Authenticated MC session snapshot required')
  assert(sessions.world_id==p.world_id and sessions.server_session_id==p.server_session_id,'World/session mismatch')
  assert(type(sessions.mc_epoch)=='string'and#sessions.mc_epoch>0,'MC process epoch required')
  local now=os.time();assert(type(sessions.updated_unix)=='number'and now-sessions.updated_unix>=-5 and now-sessions.updated_unix<=5,'MC sessions are stale')
  local active={};for _,row in ipairs(p.players)do active[row.pal_uid]=true end
  local found
  for _,row in ipairs(sessions.sessions or{})do
   if row.mc_uuid==mc_uuid:lower()and not row.legacy and row.expires_at>now and active[row.pal_uid]then
    assert(type(row.session_id)=='string'and type(row.generation)=='number'and row.generation%1==0 and row.generation>0,'Invalid MC connection generation')
    assert(not found,'Duplicate authenticated MC identity');found={pal_uid=row.pal_uid,mc_uuid=row.mc_uuid,session_id=row.session_id,generation=row.generation,
     world_id=p.world_id,server_session_id=p.server_session_id,mc_epoch=sessions.mc_epoch}
   end
  end
  return found
 end
 return api
end
return M
