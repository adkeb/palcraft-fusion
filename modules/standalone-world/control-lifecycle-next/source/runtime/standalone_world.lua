-- Standalone world glue: consumes the multiplayer owner's actual realm provider.
-- Construction is inert. Each game-thread operation revalidates the real local host.
local dir=assert(debug.getinfo(1,'S').source:match('^@(.*[/\\])'))
local M={version=1}
function M.new(o)
 assert(o and o.local_realm and o.client_worker,'Actual local realm and current client worker required')
 local realm=o.local_realm;local api={}
 local function current()
  local p=realm:current()
  if not p or p.mode~='standalone'or realm:validate(p,p.pc)~=true then return nil end
  return p
 end
 function api.companion()
  local p=current();if not p then return nil end
  local w=o.client_worker();if not w or w.stopped or not w.ctx or realm:validate(p,w.ctx.pc)~=true then return nil end
  local c=w.companion
  if not c or not c.context then return nil end
  local ok,ctx=pcall(c.context)
  if not ok or realm:same_world(ctx,p)~=true then return nil end
  return c
 end
 function api.resolve_player(uid)
  local p=current();if p and p.host_uid==uid then return p.pc end
 end
 function api.authorize_ai(params,mutation)
  local p=assert(current(),'Actual Standalone MainWorld local authority unavailable')
  if params and params.player_uid then assert(params.player_uid==p.host_uid,'Standalone operation must use actual saved host UID')end
  -- Existing technology/guild/base/slot/material/native permission checks remain
  -- in the original AI operation. No free items or automatic role migration here.
  return p
 end
 function api.native_context()
  return assert(current(),'Actual Standalone MainWorld required').game_state
 end
 function api.server_views()
  if not api.view then api.view=dofile(dir..'standalone_views.lua').new{
   local_realm=realm,client_worker=o.client_worker,game_thread=o.game_thread}end
  return api.view
 end
 function api.status()
  local p=current();return{mode='standalone',actual_realm_available=p~=nil,
   world_id=p and p.world_id,host_uid=p and p.host_uid,server_session_id=p and p.server_session_id,
   shared_collision_owner='existing_client_world',authority_faked=false}
 end
 local function control(method,features)
  local p=assert(current(),'Actual Standalone MainWorld local authority unavailable')
  local controls=assert(o.client_control,'Existing client lifecycle controls unavailable')
  return assert(controls[method],'Client lifecycle control unavailable:'..method)(features,p,api.view)
 end
 function api.start(features)return control('start',features)end
 function api.stop(features)return control('stop',features)end
 function api.control_status()return control('status')end
 return api
end
return M
