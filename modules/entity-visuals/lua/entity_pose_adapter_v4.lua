-- Adds authoritative cow/chicken variant IDs to the previous scalar contract.
local dir=assert(debug.getinfo(1,'S').source:match('^@(.*[/\\])'))
local Base=dofile(dir..'entity_pose_adapter_v3.lua')
local M={body_yaw=Base.body_yaw,actor_yaw=Base.actor_yaw}
function M.pose(row)
 local s=Base.pose(row)
 if row.kind=='minecraft:cow'then s.variant=row.cow_variant or row.variant
 elseif row.kind=='minecraft:chicken'then s.variant=row.chicken_variant or row.variant
 elseif row.kind=='minecraft:sheep'then s.variant='normal'end
 return s
end
function M.geometry(visuals,row)
 local groups,effects=visuals.geometry(row.kind,M.pose(row))
 if groups then for _,g in ipairs(groups)do g.authoritative_entity_id=row.id;g.pose_source='mc_server_scalars';g.baby_variant_pending=false end end
 return groups,effects
end
return M
