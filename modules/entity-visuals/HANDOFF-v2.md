# MC 实体视觉 V2：幼年模型与猪的气候外观

新增 `entity_visuals_v2.lua`、`entity_pose_adapter_v2.lua`、`MobVariantOracle.java`、`prepare_entities_v2.py`。既有实体 V1、block V2/V3/V4 及首运行候选保持冻结，不部署、不占 GUI。

## 实质功能

- Pig 三种 climate（temperate/warm/cold） × adult/baby，共六套原版 rig+skin。寒冷成年猪取 `ColdPigModel`，暖地/温带成年猪取 `PigModel`；三种幼年猪都取实际 `BabyPigModel`，但使用各自专属 baby PNG。
- 僵尸 adult/baby 共两套，幼年取当前 `BabyZombieModel` 与 zombie_baby 皮肤。
- 苦力怕沿用已冻结 V1 的真实模型与动作。

不是对成年猪或僵尸整体乘 0.5。当前 26.3 的幼年 model factories 已有专属几何、比例与 UV，`LivingEntity.getScale()` 仍是实体 SCALE 属性，`getAgeScale()` 幼年为 0.5、成年为 1，主要供原版动作处理。模块不会额外把幼年缩一遍。

## 使用

```lua
local V=dofile('.../entity_visuals_v2.lua')
local A=dofile('.../entity_pose_adapter_v2.lua')
V.configure({json=J,root=ENTITY_ASSET_ROOT_V2})
local groups,effects=A.geometry(V,row)
local yaw=A.actor_yaw(row)
```

V2 静态/动态输出保持 V1 的 Actor-local UE cm、前 +X、feet-origin、零基 indices、NoCollision、`g.texture_path` 与 overlay 合同；死亡翻滚/苦力怕膨胀已烘进顶点，native 不再应用。`g.rig_key` 表示选中的具体变种，`g.baby` 对应实际 rig。

`pose.baby`、`pose.variant` / `pig_variant`、`pose.scale`、`pose.age_scale` 是新增输入。猪 variant 可是 `minecraft:temperate/warm/cold` 或裸名称。Zombie variant 固定 normal。adapter 优先读取 entity_combat 的真实 `row.pig_variant, row.scale, row.age_scale`，仍不从 bbox/velocity 反推；字段尚未部署时按已知原版普通默认值工作。

V1 adapter 为 V2 adapter 的依赖，保持原 SHA。V2 主几何模块独立，不修改冻结 V1。V2 需要的目录是 `variants/rigs/skins` 同级，所有资产路径仍相对根；Windows 应部署到独立 `D:/PalworldServer-LAN/PalCraft-Dev/bridge/entity-assets-v2/`。

## 证据与边界

单核 BelowNormal 256MiB JVM 在用户安装的实际 MC 26.3 上调用 model factories/setupAnim/ModelPart.visit，只生成轻量数据。新增八套 rig、24 组姿态对照通过：最大 pose 误差 `1.60e−7`，顶点误差 `2.86e−5 cm`，法线误差 `1.85e−7`。这证明数据接口和算法，不是游戏中渲染验收。

资源私有，公开包只能包含转换源码，不包含 Minecraft 皮肤及派生 PNG。夜间低功耗、正式服 OFF、GUI 租约规则保持。装备/持有物、苦力怕带电 aura、最终 native/material 场景仍未完成。

最终 frozen/root/hash 见 `READY-v2.json`。普通字段进度记录在主工作区 `coordination/model_geometry.json`，无需逐条抄送 lead。
