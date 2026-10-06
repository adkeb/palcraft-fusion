-- Actual next server wiring. The full AI dispatcher owns the existing companion and callback.
local dir=assert(debug.getinfo(1,'S').source:match('^@(.*[/\\])'))
local M={}
function M.new(o)
 local J,R,cfg=assert(o.json),assert(o.readers),assert(o.config)
 local IO=dofile(dir..'io.lua');local Records=dofile(dir..'records.lua');local F=IO.new(J)
 local bridge,scripts,rpc=IO.root(o.bridge_root),IO.root(o.scripts_dir),IO.root(o.rpc_root)
 local exchange=IO.root(assert(cfg.exchange_root,'Trusted next exchange root required'))
 local options={json=J,readers=R,bridge_root=bridge,auth_root=rpc..'session-auth/',origin=assert(o.origin),
  companion=assert(o.companion),entities_enabled=cfg.entities_enabled~=false,food_enabled=cfg.food_enabled==true,
  bootstrap_enabled=cfg.boot_observer_enabled~=false,exchange_enabled=cfg.exchange_enabled==true,
  fluid_enabled=cfg.fluid_physics_enabled==true or cfg.fluid_enabled==true,travel_enabled=cfg.travel_enabled==true}
 options.bootstrap={root=exchange,rpc_root=rpc,process_dll=scripts..'PalCraftEscrowBoot-v1.dll'}
 if cfg.bootstrap_sampling_hold==true then
  options.bootstrap_hold_reason='actual_native_boot_api_fault_quarantined_pending_repair'
 end
 if options.exchange_enabled then
  -- Registration can follow normal paid construction after startup. Keep this
  -- component pending until real dependencies exist; the other features can run.
  options.exchange_ready=function()
   local pre=F.read(exchange..'escrow-boot-prelaunch.json')
   if not pre or not pre.boot_id or not pre.epoch then return false,'stopped_process_checkpoint_missing'end
   local paid=F.read(exchange..'escrow-config.json')
   if not paid then return false,'real_paid_escrow_enrollment_missing'end
   options.exchange={root=exchange,config=paid,boot_id=pre.boot_id,epoch=pre.epoch,
    boot_certificate=F.read(exchange..'escrow-boot-certificate.json')}
   return true
  end
 end
 if options.fluid_enabled then
  options.fluid={root=rpc,json=J,shared_dir=scripts..'fluid/',dll_path=scripts..'../../../../PalCraftFluidPhysics-v1.dll',
   log_path=scripts..'../../../UE4SS.log'}
 end
 if cfg.environment_enabled==true then
  local guard,guard_companion
  options.environment_contact=function(query,target)
   local c=o.companion();if not c or not c.world then return false,'authoritative_fluid_world_not_loaded'end
   if guard_companion~=c then
    local Core=dofile(scripts..'fluid/fluid_physics_core.lua')
    guard=Core.environment_contact{world=c.world,origin=o.origin,shared_dir=scripts..'fluid/',game_thread=o.game_thread,
     contact_driver=dofile(scripts..'fluid/world_fluid.lua')};guard_companion=c
   end
   return guard(query,target)
  end
 end
 if options.travel_enabled then
  local Journal=dofile(scripts..'travel/journal.lua')
  local journal=Journal.new{json=J,path=rpc..'travel/state.ndjson',ack_path=rpc..'travel/travel-acks.ndjson',flush_file=o.flush_file}
  local out=Records.append{json=J,path=rpc..'travel/travel-events.ndjson',flush_file=o.flush_file}
  options.travel_input=Records.tail{json=J,path=rpc..'travel/travel-input.ndjson'}
  local view=o.travel_view or dofile(dir..'server_views.lua').new{companion=o.companion,json=J,origin=o.origin,root=rpc,
   chunk_dir=scripts..'chunks/',models_path=scripts..'models.lua',geometry_version=3,
   asset_root=bridge..assert(cfg.model_asset_directory,'Frozen model asset directory missing')..'/',
   collision_dll=scripts..'../../../../PalCraftChunkCollision-v1.dll',log_path=scripts..'../../../UE4SS.log',
   collision_verified=cfg.collision_verified==true}
  local P=dofile(scripts..'travel/protocol.lua')
  local travel_config=P.copy(F.read(bridge..'travel-config.json')or dofile(scripts..'travel/config.lua'))
  travel_config.home_origin=P.copy(o.origin) -- same actually loaded low-Z home as the client
  options.travel={module_dir=scripts..'travel/',journal=journal,send=out.send,
   view=view,config=travel_config,rebase_supported=cfg.rebase_enabled==true,
   recovery_scenes=view.recovery_scenes,retain_scene=view.retain_scene}
  options.verify_travel_request=function()return false end -- Guest RPC cannot impersonate the trusted Java file writer.
 end
 return options
end
return M
