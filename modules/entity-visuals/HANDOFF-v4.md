# 常见动物年龄与气候视觉 V4

本批只新增 owned `entity-visuals` 源码与私有资源，保留既有 entity V1/V2/V3、block 数据与首运行候选冻结。没有 GUI/RPC/启停操作。

## 完整批次

- 牛 temperate/warm/cold × adult/baby 六套，成年分别来自 `CowModel/WarmCowModel/ColdCowModel`，幼年按实际注册使用 `BabyCowModel`，每个气候使用专属 adult/baby skin。
- 鸡 temperate/warm/cold × adult/baby 六套，cold 成年为 `ColdChickenModel`、其余 `AdultChickenModel`，幼年取 `BabyChickenModel` 与专属 skin。实际 baby rig 没有独立 head bone，不能强套成年 head look。
- 羊 body/fur × adult/baby 四套；幼年 fur 按原版 ModelLayers 注册使用 `BabySheepModel` 形状配 sheep_wool_baby 皮肤，保留实际头部吃草动作与年龄 scale。

共 16 套新增实际 rig，此前九类生物、猪变种、幼年僵尸与所有层级数据一并保留。幼年 geometry 已小，`getScale` 是全局实体属性，不额外乘 0.5；`getAgeScale` 只按原版动作用途传递。

## 接口

`entity_visuals_v4.lua` 依赖 `common_mob_pose_v4.lua`；`entity_pose_adapter_v4.lua` 依赖冻结 V3/V2/V1 adapters。统一 API、world feet/body yaw、Actor-local cm/前 +X、零基 indices、NoCollision、material effects 规则全部保持。

```lua
V.configure({json=J,root=ENTITY_ASSET_ROOT_V4})
local groups,effects=A.geometry(V,row)
```

`row.pig_variant/cow_variant/chicken_variant` 为实际 registry ID；各自 pose.variant 用 bare climate 或 `minecraft:temperate/warm/cold`。年龄读取 actual `row.baby`，全局 `scale` 与 `age_scale` 沿用实体负责人实际 getter。剪毛羊跳过对应年龄的 fur；未剪毛幼年羊使用幼年毛层，不混成年 fur。

所有 PNG 路径仍由选择后的 `g.texture_path` 给材质，以实际文件路径缓存。V4 texture roots 留本地，不公开捆绑 MC skin/派生像素。部署时用独立 Windows `D:/PalworldServer-LAN/PalCraft-Dev/bridge/entity-assets-v4/`，相对 `skins/rigs/variants` 不带 Mac 绝对路径。

## 证据与状态

`AnimalVariantOracle.java` 复用 `VanillaPoseExport`，单核 BelowNormal 256MiB JVM 对当前合法 MC 26.3 factories/renderstates 进行轻量导出。48 个新增原版姿态对照通过，最大 pose 误差 `2.59e−8`、顶点误差 `2.49e−5 cm`、法线误差 `1.43e−7`。

没有复测旧矩阵或做大规模压力/图形验证。最终 native attach/material/WPO/真实性画面仍 pending；装备/弓/持有物、染色/Jeb 羊毛材质、eyes additive 材质与末影人搬运 block 几何也未完成。

最终 frozen/root/hash 见 `READY-v4.json`，普通机器状态为 `coordination/model_geometry.json`。night_low_power 与当前 GUI 租约保持。
