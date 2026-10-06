# 真实 Minecraft 实体视觉 V1

范围：原版 MC 26.3 成年温带猪、普通僵尸、普通苦力怕。实体类型/UUID/位置/目标/生命值由 entity_combat 保持权威；此模块只生成真实 MC 外形与视觉姿态，不使用 Pal surrogate 外形作为成品。

## 数据与接入

独立 `entity-visuals/assets`，冻结版本由本目录 `READY-v1.json` 指向。资产是用户已安装 Minecraft jar 的私有转换结果，不能在公开玩家包里捆绑；公开包只能提供 `prepare_entities.py`/Java 提取源码与用户资源导入流程。

```lua
local V=dofile('.../entity_visuals.lua')
V.configure({json=J,root=ENTITY_ASSET_ROOT})
local groups,effects=V.geometry(row.kind,pose)
-- native renderer 使用权威 row 的世界脚底和 body yaw 放置真实组件。
```

输出兼容原 native mesh groups：每顶点 `{X,Y,Z,Nx,Ny,Nz,U,V}`，UE 厘米、Actor-local、**前方 +X、脚底 Z≈0**；indices 为 0 基。`g.texture` 原 MC Sprite ID；`g.texture_path` 为本地 PNG；`alpha_mode=cutout,tint=-1,collision=false,entity_visual=true`，`face_ranges.part` 保留部件。默认全实体合为一个皮肤组，避免每条腿单独 draw call；有层级 rig/poses 信息可供未来 native 骨架优化。

Entity owner 已确认世界脚底 `(O.X+100x,O.Y-100z,O.Z+100(y-64))`，Actor yaw `-90−MC body yaw`。本模块只输出 local 几何，**不再加 O、y−64 或世界 yaw**。从 MC model-space 到 local UE：`X=−modelZ*100,Y=modelX*100,Z=(1.501−modelY)*100`。Native 若把组件挂到 capsule-center actor，需要正确处理 actor 到脚底的相对偏移。

`pose={walk_pos,walk_speed,head_yaw,head_pitch,attack_time,age,aggressive,hurt,death_time,swelling,scale?,parts?}`。角度以度输入，head_yaw 为相对 body 的头部朝向；time/age/death_time 为 MC tick，swing attack_time 为原版 0..1。`parts` 可直接提供原版每骨骼 local SRT（MC model blocks，数组 `x,y,z,xRot,yRot,zRot,xScale,yScale,zScale`，旋转为弧度），覆盖标量求值，以支持后续完整装备/姿态输入。

`rig(kind)` 输出部件层级、rest pose 与实际 cuboid faces/UV；`pose(rig,state)` 输出每部件姿态。MC `Mth` 的 sine quantization 在轻量 Lua 标量路径中复现，苦力怕模型实际 left/right 字段绑定与猪不同，已按原版处理。`current_swing=true,swing_arm='left'|'right'` 可启用僵尸原 Humanoid 的 torso/arm pivot 扭转；完整 currentSwing/装备类型应由原版 client pose 数据提供。

## Renderer-only 效果

`g.render_effects` 有 `red_overlay/white_overlay/scale_xz/scale_y/death_roll`。死亡翻滚和苦力怕膨胀已应用到生成顶点，native 不要再次应用。受伤红色/苦力怕白色闪烁仍交给真实材质，不能仅凭字段宣称在游戏生效。

原版 `OverlayTexture` 与 shader 规则在 `render-effects.json`：16×16，red overlay `v=3` 的像素 `ARGB0xB2FF0000`；shader 做 `mix(overlay.rgb,base.rgb,overlay.a)`，alpha 保持皮肤 alpha。无 red 用 v10，white u 为 `int(white_progress*15)`，白像素 alpha 为 `int((1−u/15*0.75)*255)/255`。苦力怕 white_progress：`int(swelling*10)%2==0 ? 0 : clamp(swelling,.5,1)`。不能用 foliage 风动/换色材质冒充最终实体皮肤材质。

## 证据和限制

`MobRigOracle.java` 直接调用当前原版 PigModel、ZombieModel、CreeperModel factories/setupAnim/ModelPart.visit，输出 3 rigs、22 parts、120 quads、3 skins 和 24 状态样本。单核、BelowNormal、256MiB JVM，没有启动图形游戏、没有修改世界。

`verify_entities.lua` 24 个实际样本已通过：最大 pose 误差 `1.48e−7`、顶点误差 `2.70e−5 cm`、法线误差 `1.85e−7`。此证据是数据/算法层，不是游戏内截图验收。

未完成：baby/猪气候模型、装备和持有物 layers、charged creeper aura、native attach/update/material、最终运行画面。保持 night_low_power，运行实测等待主 lease，正式服 OFF，block model V2/V3/V4 冻结包不变。

## 实体 next-source 标量适配器

新增独立 `lua/entity_pose_adapter.lua`，不改变已冻结 `entity_visuals.lua` 或其 hash：

```lua
local groups,effects=Adapter.geometry(Visuals,row)
local yaw=Adapter.actor_yaw(row)
```

直接映射 entity_combat 已从当前 MC 26.3 字段/getter 取得的 `age,walk_pos,walk_speed,head_yaw,head_pitch,attack_time,hurt_time,death_time,current_swing,swing_arm,aggressive,swelling`。head_yaw 已相对 body_yaw，不能再次减 body_yaw；世界 Actor yaw 优先 `-90-body_yaw`，缺少时沿用基础 `yaw`。没有步态字段时缺省 0，不使用 velocity 推断冒充原版步态。HP/位置原对象不写。

当前 producer 的 swing_arm 首实现为 getMainArm/dominant arm；OFF_HAND 的实际 swing arm 需要 `currentSwing.hand().asArm(mainArm)`，已提醒 entity owner完善；适配器沿用 producer 的值并保留此限制。`baby_variant_pending` 明确成年 rig 尚未覆盖 baby 模型。本次仅一个轻量映射 fixture，没有额外图形/大规模测试。

更新：entity_combat 的 next-source 已修正 OFF_HAND，`LivingEntity.getCurrentSwing()` 非 null 时取 `swing.hand().asArm(living.getMainArm())` 导出真正 `swing_arm`，另有 `swing_hand=main_hand/off_hand`；无 currentSwing 时才 dominant fallback。现有适配器直接消费 `swing_arm`，无须修改冻结代码或 hash。该修正仍待 integration 的必要单 worker Javac 检查，尚未标为部署/运行完成。

独立适配器 ready/hash 见 `POSE-ADAPTER-READY-v1.json`。V1 rig/skin/主 Lua 冻结仍然保持原值。
