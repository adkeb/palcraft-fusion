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
 if o.standalone_world then
  assert(o.local_realm,'Actual standalone realm provider required')
  options.local_realm=o.local_realm;options.world_observer_owner='standalone_server'
  options.companion=o.standalone_world.companion
  options.resolve_player=o.standalone_world.resolve_player
 end
 options.bootstrap={root=exchange,rpc_root=rpc,process_dll=scripts..'PalCraftEscrowBoot-v1.dll'}
 if cfg.bootstrap_sampling_hold==true then
  options.bootstrap_hold_reason='actual_native_boot_api_fault_quarantined_pending_repair'
 end
 if options.exchange_enabled and o.standalone_world then
  options.exchange_ready=function()
   local paid=F.read(exchange..'escrow-config.json')
   if not paid or not paid.runtime_scope or paid.runtime_scope.mode~='standalone'then return false,'actual_standalone_paid_enrollment_missing'end
   local proof=o.local_realm:current()
   if not proof or paid.runtime_scope.pal_uid~=proof.host_uid or paid.runtime_scope.world_directory~=proof.world_id then return false,'actual_standalone_paid_scope_changed'end
   local service=o.standalone_observer and o.standalone_observer.service
   if not service or service.ready~=true or not service.binding then return false,'actual_standalone_process_binding_pending'end
   options.exchange={root=exchange,config=paid,boot_id=service.binding.boot_id,epoch=service.binding.epoch}
   return true
  end
 elseif options.exchange_enabled then
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
  options.fluid={root=o.standalone_world and bridge or rpc,json=J,shared_dir=scripts..'fluid/',dll_path=o.standalone_world and assert(rawget(_G,'PalCraftStandaloneBootstrap').scope.fluid_dll_windows)or(scripts..'../../../../PalCraftFluidPhysics-v1.dll'),
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
  local view=o.travel_view or(o.standalone_world and o.standalone_world.server_views())or dofile(dir..'server_views.lua').new{companion=o.companion,json=J,origin=o.origin,root=rpc,
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
