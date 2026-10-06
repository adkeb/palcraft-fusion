local A=dofile('work/minecraft-fusion/entity-visuals/lua/entity_pose_adapter.lua')
local row={id='mc:fixture',kind='minecraft:zombie',age=31,walk_pos=2.4,walk_speed=.6,
 body_yaw=125,yaw=133,head_yaw=-17,head_pitch=9,attack_time=.4,hurt_time=6,death_time=0,
 current_swing=true,swing_arm='left',aggressive=true,swelling=.1,hp=7,x=1,y=64,z=2,vx=99}
local pose=A.pose(row)
assert(pose.age==31 and pose.walk_pos==2.4 and pose.walk_speed==.6)
assert(pose.head_yaw==-17 and A.actor_yaw(row)==-215)
assert(pose.hurt and pose.current_swing and pose.swing_arm=='left'and pose.aggressive)
assert(row.hp==7 and row.x==1 and row.yaw==133)
assert(A.pose({vx=99,vy=99,vz=99}).walk_pos==0)
assert(A.actor_yaw({yaw=45})==-135)
print('{"status":"passed","scope":"actual MC scalar mapping, relative head yaw, no velocity walk, authority unchanged","night_low_power":true}')
