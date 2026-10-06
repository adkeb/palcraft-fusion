-- Read the one authenticated proxy bootstrap mailbox. HOST and native MC leases stay distinct.
local M={}
function M.new(o)
 local Session=assert(o.session);local read=assert(o.read);local now=o.now or os.time
 local path=assert(o.path);local api={last_error=nil}
 function api.binding(host)
  if not host then return nil,'host_unbound'end
  local q=read(path)
  local ok,result=pcall(function()
   assert(q and q.schema==1 and q.protocol==2 and q.authenticated_host==true and q.native_mc_verified==true,'native_MC_bootstrap_unverified')
   assert(type(q.updated_unix)=='number'and now()-q.updated_unix>=-5 and now()-q.updated_unix<=3,'native_MC_bootstrap_stale')
   local h=assert(q.host_scope,'bootstrap_HOST_scope_missing')
   assert(h.session_id==host.session_id and h.generation==host.generation and h.pal_uid==host.pal_uid
    and h.mc_uuid==host.mc_uuid and h.world_id==host.world_id and h.server_session_id==host.server_session_id,'bootstrap_HOST_generation_mismatch')
   local b=assert(q.native_binding,'native_MC_lease_missing')
   assert(b.v==2 and b.legacy==false and type(b.mc_epoch)=='string'and #b.mc_epoch>0,'native_MC_epoch_missing')
   assert(b.pal_uid==host.pal_uid and b.mc_uuid==host.mc_uuid and b.mc_name==host.mc_name
    and b.world_id==host.world_id and b.server_session_id==host.server_session_id,'native_MC_identity_mismatch')
   assert(type(b.session_id)=='string'and #b.session_id==36 and math.tointeger(b.generation)and b.generation>=1
    and type(b.expires_at)=='number'and b.expires_at>now(),'native_MC_lease_expired')
   local view=assert(q.world_view,'confirmed_WorldView_missing')
   assert(view.player==b.mc_uuid and type(view.world_session)=='string'and #view.world_session>0
    and type(view.dim)=='string'and math.tointeger(view.view)and view.view>=1 and type(view.waiting_ack)=='boolean','confirmed_WorldView_invalid')
   return b
  end)
  if not ok then api.last_error=tostring(result);api.current=nil;return nil,api.last_error end
  api.current=q;api.last_error=nil;return result
 end
 function api.view(host)
  local binding,why=api.binding(host);if not binding then return nil,why end
  return api.current.world_view
 end
 function api.status()return{path=path,error=api.last_error,native_verified=api.current~=nil,
  waiting_ack=api.current and api.current.world_view.waiting_ack}end
 return api
end
return M
