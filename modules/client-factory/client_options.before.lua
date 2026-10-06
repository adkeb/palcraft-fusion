-- Concrete next-profile wiring over the existing native sender and authenticated bootstrap.
local dir=assert(debug.getinfo(1,'S').source:match('^@(.*[/\\])'))
local M={}
function M.new(o)
 local J,root,cfg=assert(o.json),assert(o.bridge_root),assert(o.config)
 local IO=dofile(dir..'io.lua');root=IO.root(root);local F=IO.new(J)
 local commands=dofile(dir..'records.lua').commands{json=J,path=root..'command.json'}
 local options={json=J,bridge_root=root,origin=assert(o.origin),identity=cfg.identity,view_bridge=assert(o.view_bridge),
  native_mc_bootstrap_enabled=cfg.world_scoped_cam_enabled==true,entities_enabled=cfg.entities_enabled~=false,
  entity_visuals_enabled=cfg.entity_visuals_enabled==true,sign_enabled=cfg.sign_text_enabled==true,
  fluid_enabled=cfg.fluid_enabled==true,travel_enabled=cfg.travel_enabled==true,command_bus=commands}
 local function runtime()return assert(_G.PalCraftClientFeatures,'Client runtime not initialized')end
 if options.fluid_enabled then
  local scripts=assert(o.scripts_dir)
  options.fluid={root=root,json=J,shared_dir=scripts..'fluid/',dll_path=scripts..'../../../../PalCraftFluidPhysics-v1.dll',
   log_path=scripts..'../../../UE4SS.log'}
 end
 if options.sign_enabled then
  options.sign={allow_candidate=cfg.lab_candidate==true,profiles=cfg.sign_profiles,verified_profiles=cfg.verified_sign_profiles,
   send_binding=commands.send,images_ready=function()
    return cfg.sign_text_transport_version==1,'sign_text_image_receiver_not_installed'
   end,
   confirmed_view=function(companion)
    local view=runtime():bootstrap_view()
    if not view or view.waiting_ack or view.world_session~=companion.world.session or view.dim~=companion.world.dimension then return end
    -- This tuple is MC-confirmed; the scene adapter separately obtains actual O/committed geometry.
    return{applied=true,world_session=view.world_session,dim=view.dim,view=view.view,mc_uuid=options.identity.mc_uuid}
   end}
 end
 if options.travel_enabled then
  local input=dofile(dir..'records.lua').tail{json=J,path=root..'travel-events.ndjson'}
  options.travel_transport={send=function(row)
   local types={client_ready='travel_ready',client_observed='travel_observed',client_abort='travel_abort'}
   local query={};for k,v in pairs(row)do query[k]=v end
   query.t=assert(types[row.phase],'Unknown native travel signal');return commands.send(query)
  end,poll=function(consume)input.poll(consume,64)end}
  options.travel={view=assert(o.travel_view,'Real native travel view constructor required'),readers=o.readers,
   module_dir=assert(o.scripts_dir)..'travel/'}
 end
 return options
end
return M
