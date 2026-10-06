# 实际 MC 掉落物与投射物视觉增量 V1

先检查了当前 consumer：`client/entities.lua` 仅处理 mob；`server/main.lua:update_items()` 的 drops.json 仍创建碰撞关闭的 cube，fixed +0.3Z/os.clock旋转，因此 projectile payload 与 item count 并不表示真实外观已实现。此批只新增 owned entity-visuals，既有所有 frozen/root/native5/实体V3基线不改。

## Provider 与 Native 适配

`lua/portable_visuals.lua`：

```lua
Visuals.configure({json=J,root=PORTABLE_ASSET_ROOT})
local groups,effects=Visuals.geometry(row)
```

类别 `row.category='projectile'` 使用真实 ArrowModel/TridentModel，其他使用 actual item definition model。输出兼容已有 native5 `spawn_groups/update_groups`：UE cm、以实体位置为原点、NoCollision、texture_path/material_root/entity_visual=true。

**yaw/pitch、箭 shake、item ground/bob/spin 已烘进顶点与法线**；输出是相对实体中心的 world-oriented local mesh，`g.actor_yaw=0,effects.world_orientation_baked=true`，native pose 的世界 yaw 设 0，不能再按实体 row.yaw 转第二遍。不包含 world origin 或 y−64，placement 仍用权威 x/y/z。

Arrow/SpectralArrow 同一 actual 原版 model 几何，分开原皮肤；Trident 保留实际独立叉尖/杆/UV。支持 foil 字段但 glint 材质尚未接，`foil_material_pending=true` 不表示视觉已完成。

## Drop models

36 常见静态物品（木石/资源/工具/食物/箭/三叉戟等，完整 ID 在 manifest）从当前 MC `/items/*.json` 选择 ground model，继承原版 display/texture/elements。generated item 使用原 sprite alpha 边界、7.5/8.5 模型像素厚度、正反面与精确 source-pixel side faces，side UV 采用原版 0.1 texel shrink。cuboid item 保留真实 elements、元素 rotation、face UV 与每面纹理。

用原 ItemTransform rotationXYZ 顺序、ground translation/scale/centering；原 ItemRenderer bob、model minY+1/16 lift、ItemEntity.getSpin(age,bobOffset)。数量依原阈值变成 1..5 视觉副本，使用原 seed random/source Z厚度分支及副本偏移。

未得到原版时间/seed 字段时只保留缺省静态位，标记 `pose_timing_pending/render_seed_pending`，不把 os.clock 替代说成原版动画。动态 components/条件 item selector、药水/tipped-arrow颜色、foil glint 仍 pending。

## Observer

`lua/portable_observer.lua` 是新的只读世界显示 consumer，调用已有 models native5 接口，不另造 renderer。`Observer.new({models,visuals,origin,context,session,dimension,now,on_drop_committed})`；`apply(snapshot)` 接受 authenticated MC server `drops` 或 `entity_snapshot` envelope，稳定 string UUID/id + epoch/revision/dimension/freshness。

同拓扑/皮肤更新复用 actor+mesh；数量/类型/皮肤变化才 hidden prepare 新 mesh 然后 commit 替换。只有成功创建并显示真实 mesh 后才调用 `on_drop_committed(row,handle)`，runtime owner可据此释放 legacy cube。移除/拾取/expire按权威下一完整snapshot释放显示，没有修改 MC drop entity 或 inventory。

旧 bare drops.json 目前没有 authority/session/epoch、id只是integer，因此新观察器直接拒绝它；world owner正在协调新增实际 envelope/UUID/age/bob_offset/render_seed。不能将 file freshness当作 authority，不能为显示而赠物品。投射物位置/生命周期/命中仍 MC authority，观察器没有任何 damage path。

## 必要证据

`PortableVisualOracle.java` 在 standalone 单核 BelowNormal JVM 直接原版 Arrow/Trident factories/pose + 当前 renderer rotation流程；四个姿态顶点最大误差 `2.02e−5 cm`、法线 `1.24e−7`。

Item oracle 调用实际私有 `ItemModelGenerator.getSideFaces()` 检查三种 sprite（pickaxe/coal/arrow）。只使用纯 CPU alpha-mask virtual SpriteContents，没有执行 NativeImage/GPU 构造器；边界集合与转换器一致。原版 bytecode给出 side UV/厚度/ground/bob/spin，未跑大矩阵。

轻量 native adapter fixture 证明一次 spawn、一次 in-place update、一次移除，legacy释放 callback只在commit后发生；这不是游戏画面证明。

Assets 私有，public包只导出器/adapter源码。最终 snapshot/hash 在 `READY-portable-v1.json`；原版 world字段接线、native材质与真实场景验收仍 pending。night低功耗无GUI/RPC/重启/第二guest，无inventory或伤害权限改动。
