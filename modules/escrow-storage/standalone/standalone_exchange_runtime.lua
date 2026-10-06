-- Compose the existing service, paid helper and v3 exchange inside the approved
-- singleplayer game-thread lifecycle. No transport, UID or container creation.
local dir=assert(debug.getinfo(1,'S').source:match('^@(.*[/\\])'))
local M={}
function M.new(o)
 local J,R,s=assert(o.json),assert(o.readers),assert(o.scope)
 assert(s.mode=='standalone','Current testing scope is singleplayer only')
 local root=assert(s.exchange_root):gsub('\\','/'):gsub('/+$','')..'/'
 local service=dofile(dir..'standalone_service.lua').new{scope=s,json=J,readers=R,durable_dll=assert(o.durable_dll),credit_dll=assert(o.credit_dll)}
 local helper=dofile(dir..'escrow_setup.lua').new{authority_mode='standalone',world_directory=s.world_directory,
  scripts_dir=s.scripts_dir,root=root,json=J,readers=R,durable_dll=o.durable_dll,allow_build=true}
 local exchange
 local function config()
  local f=io.open(root..'escrow-config.json','rb');if not f then return end
  local c=J.decode(f:read('*a'));f:close()
  assert(c.protocol==3 and c.runtime_scope and c.runtime_scope.mode=='standalone'and
   c.runtime_scope.pal_uid==s.pal_uid and c.runtime_scope.world_directory==s.world_directory,'Enrollment belongs to another host/world')
  return c
 end
 local api={setup=helper}
 function api.tick()
  assert(IsInGameThread());service.tick()
  local c=config()
  if not c then api.phase='awaiting_real_paid_enrollment';return end
  if not exchange then
   exchange=dofile(dir..'exchange_v3.lua').new{root=root,json=J,readers=R,config=c,
    boot_id=service.binding.boot_id,epoch=service.binding.epoch}
  end
  if not o.external_exchange_tick then exchange.tick()end
  api.phase='active_actual_v3';return api
 end
 function api.ready()return service.ready==true end
 function api.get_exchange()return exchange end
 function api.start_early()return api end -- Existing external tick owns timing; no second timer.
 function api.status()return {phase=api.phase or'awaiting_normal_load',mode='standalone',
  ready=service.ready==true,
  actual_process_bound=service.ready==true,paid_enrolled=exchange~=nil,native_credit_runtime_verified=false}end
 function api.stop()if exchange then exchange.stop()end end
 return api
end
function M.start_early_boot(o)return M.new(o)end -- Original observer tick/ready/status/stop shape.
return M
