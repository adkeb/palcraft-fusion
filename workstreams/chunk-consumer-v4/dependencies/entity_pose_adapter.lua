-- Maps entity_combat's actual MC26.3 scalar snapshot into visual-only pose.
-- No velocity-estimated walk, authority mutation, HP or native actor writes.
local M={}
function M.pose(row)
 return{
  age=row.age or 0,
  walk_pos=row.walk_pos or 0,
  walk_speed=row.walk_speed or 0,
  head_yaw=row.head_yaw or 0, -- Already relative to body_yaw in producer.
  head_pitch=row.head_pitch or row.pitch or 0,
  attack_time=row.attack_time or 0,
  hurt=row.hurt==true or(row.hurt_time or 0)>0,
  hurt_time=row.hurt_time or 0,
  death_time=row.death_time or 0,
  current_swing=row.current_swing==true,
  swing_arm=row.swing_arm or'right',
  aggressive=row.aggressive==true,
  swelling=row.swelling or 0,
  parts=row.pose_parts,
 }
end
function M.body_yaw(row)return row.body_yaw or row.yaw or 0 end
function M.actor_yaw(row)return -90-M.body_yaw(row)end
function M.geometry(visuals,row)
 local groups,effects=visuals.geometry(row.kind,M.pose(row))
 if groups then for _,g in ipairs(groups)do
  g.authoritative_entity_id=row.id
  g.pose_source='mc_server_scalars'
  g.baby_variant_pending=row.baby==true
 end end
 return groups,effects
end
return M
