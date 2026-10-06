-- Reuse authenticated-sessions v2 and the installer's authenticated-host status.
-- This module consumes trusted local mailboxes; it performs no credential parsing or cryptography.
local M={version=2}
local function uuid(s)return type(s)=='string'and s==s:lower()and s:match('^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$')~=nil end
local function text(s)return type(s)=='string'and #s>0 and #s<=512 end
local function fresh(v,now,ttl)return type(v)=='number'and now-v>=-5 and now-v<=ttl end
function M.same(a,b)
 if not a or not b then return a==b end
 for _,k in ipairs({'world_id','pal_uid','mc_uuid','server_session_id','session_id','generation','mc_epoch'})do
  if a[k]~=b[k]then return false end
 end
 return true
end
local function handle(row,world,boot,epoch,now)
 assert(type(row)=='table'and row.v==2 and row.legacy==false,'Strict authenticated session required')
 assert(uuid(row.mc_uuid)and uuid(row.pal_uid)and uuid(row.session_id),'Session UUID invalid')
 assert(math.tointeger(row.generation)and row.generation>=1,'Session generation invalid')
 assert(row.world_id==world and row.server_session_id==boot,'Session world/Pal boot mismatch')
 assert(type(row.expires_at)=='number'and row.expires_at>now,'Session expired')
 return{v=2,world_id=world,pal_uid=row.pal_uid,mc_uuid=row.mc_uuid,mc_name=row.mc_name,
  server_session_id=boot,session_id=row.session_id,generation=row.generation,expires_at=row.expires_at,
  legacy=false,mc_epoch=epoch}
end
function M.registry(snapshot,presence,now)
 assert(type(presence)=='table'and presence.v==2 and presence.authority==true and fresh(presence.updated_unix,now,5),'Pal authority presence unavailable')
 assert(type(snapshot)=='table'and snapshot.v==2 and fresh(snapshot.updated_unix,now,5),'Authenticated MC sessions unavailable/stale')
 assert(text(snapshot.world_id)and snapshot.world_id==presence.world_id and snapshot.server_session_id==presence.server_session_id,'Authority world/Pal boot mismatch')
 assert(text(snapshot.mc_epoch),'MC authority epoch missing')
 local online={};for _,p in ipairs(presence.players or{})do
  assert(uuid(p.pal_uid)and p.possessed==true and p.saved_account==true and not online[p.pal_uid],'Ambiguous Pal presence')
  online[p.pal_uid]=true
 end
 local by_mc,by_pal,seen_mc,seen_pal={},{},{},{}
 for _,row in ipairs(snapshot.sessions or{})do
  local h=handle(row,snapshot.world_id,snapshot.server_session_id,snapshot.mc_epoch,now)
  assert(not seen_mc[h.mc_uuid]and not seen_pal[h.pal_uid],'Duplicate MC/Pal identity binding')
  seen_mc[h.mc_uuid]=true;seen_pal[h.pal_uid]=true
  if online[h.pal_uid]then by_mc[h.mc_uuid]=h;by_pal[h.pal_uid]=h end
 end
 return{by_mc=by_mc,by_pal=by_pal,world_id=snapshot.world_id,server_session_id=snapshot.server_session_id,mc_epoch=snapshot.mc_epoch,updated_unix=snapshot.updated_unix}
end
function M.host(status,expected,now)
 assert(type(expected)=='table'and uuid(expected.pal_uid)and uuid(expected.mc_uuid)and text(expected.world_id),'Configured personal identity missing')
 assert(type(status)=='table'and status.schema==1 and status.protocol==2 and status.state=='bound'and status.authenticated_host==true,'Local host is not authenticated')
 assert(fresh(status.updated_unix,now,3),'Local host binding is stale')
 local identity=assert(status.identity,'Host identity missing')
 for _,k in ipairs({'world_id','pal_uid','mc_uuid','mc_name'})do assert(identity[k]==expected[k],'Host identity mismatch: '..k)end
 assert(status.server_session_id==expected.server_session_id,'Host Pal boot mismatch')
 local h=handle({v=2,legacy=false,world_id=identity.world_id,pal_uid=identity.pal_uid,mc_uuid=identity.mc_uuid,
  mc_name=identity.mc_name,server_session_id=status.server_session_id,session_id=status.session_id,
  generation=status.generation,expires_at=status.expires_at},identity.world_id,status.server_session_id,nil,now)
 h.mc_epoch_verified=false -- the host challenge does not attest the MC authority epoch
 return h
end
return M
