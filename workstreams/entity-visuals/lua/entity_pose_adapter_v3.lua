-- Versioned scalar adapter: V1/V2 remain immutable.
local dir=assert(debug.getinfo(1,'S').source:match('^@(.*[/\\])'))
local Base=dofile(dir..'entity_pose_adapter_v2.lua')
local M={body_yaw=Base.body_yaw,actor_yaw=Base.actor_yaw}
function M.pose(row)
 local s=Base.pose(row)
 s.holding_bow=row.holding_bow==true
 s.head_eat_position=row.head_eat_position
 s.head_eat_angle=row.head_eat_angle
 s.sheared=row.sheared==true
 s.wool_color=row.wool_color
 s.flap=row.flap or 0;s.flap_speed=row.flap_speed or 0
 s.creepy=row.creepy==true;s.carrying=row.carrying==true
 return s
end
function M.geometry(visuals,row)
 local groups,effects=visuals.geometry(row.kind,M.pose(row))
 if groups then for _,g in ipairs(groups)do g.authoritative_entity_id=row.id;g.pose_source='mc_server_scalars'end end
 return groups,effects
end
return M
