# 常见生存实体视觉 V3

新增成年骷髅、蜘蛛、温带牛、羊、温带鸡、末影人的真实 MC 26.3 rig/skin/层级 pose；羊毛另有实际 `SheepFurModel` 外层。保留前批猪/僵尸/苦力怕与 baby/climate 数据。此前所有冻结、当前 `.8.1` 运行候选与原生公共接口未改。

## 统一 API

```lua
local V=dofile('.../entity_visuals_v3.lua')
local A=dofile('.../entity_pose_adapter_v3.lua')
V.configure({json=J,root=ENTITY_ASSET_ROOT_V3})
local groups,effects=A.geometry(V,row)
local yaw=A.actor_yaw(row)
```

同样是 UE cm、Actor-local、脚底原点、前 +X、零基 indices；authority/UUID/HP/位置由实体负责人保持。V3 主模块依赖同目录 `common_mob_pose.lua`。V3 row adapter 依赖冻结 V2/V1 adapter。`geometry_from_rig(rig,state)` 是新增复用接口，方便 layer 与直接 vanilla pose 数据统一生成网格。

渲染用法与约束仍沿前版：权威 feet/yaw 由 native 接；模型已应用 scale/deathroll，native 不重复变换；hurt/white effects 交实际材质。蜘蛛的原版死亡翻转为 180°，其余本批为 90°。

## 实际覆盖

- 骷髅细肢骨骼、真实皮肤、walk/look、无弓 aggressive attack。
- 蜘蛛身体/头/八条腿，原版相位 yaw/roll 行走，head look。
- 牛四足步态、角/头/身体等原网格。
- 羊 body+独立 fur 两组，四足步态与实际 headEatPositionScale/headEatAngleScale；sheared 时跳过 fur。
- 鸡喙/肉垂/翼/腿，四足型之外的两足步态、头部 look 和 flap/flapSpeed 驱动翼。
- 末影人细长骨骼，原版半幅度/夹紧步态与 arm bob、creepy 张嘴/头帽偏移。carrying 可用原版持物手臂姿态，实际搬运的 block mesh 尚未加入。

新标量：`holding_bow,head_eat_position,head_eat_angle`（弧度）、`sheared,wool_color,flap,flap_speed,creepy,carrying`。缺少专用字段时不编造动作，保留普通 walk/look；一般状态仍用原版 age/walk/attack/body/head/hurt/death。

`layers.json` 包含 spider/enderman 的合法原版 eyes Sprite 与路径，声明 `minecraft_eyes/additive_material_required`。默认尚未把它们冒充已渲染的 glow。羊毛默认白色实际皮肤，g.wool_color 保留字段；dyed/Jeb runtime 材质未实现。

## 可复用原版导出器

`java/VanillaPoseExport.java` 可用于任何实际 MC `Model`/`EntityRenderState`：

- `rig(model)` 取得实际 private ModelPart cuboids、parent、rest SRT 与原 UV。
- `sample(model,state)` 调用原版 setupAnim，返回实际每 part local SRT 和参考 posed faces。

这是单线程数据接口，不创建游戏、不画图、不修改实体。若 integration 将其放进既有 MC guest，可用真实 renderstate 输出 parts，覆盖 Lua 标量路径并逐步扩充复杂姿态；不能把 export 成功等同于实机接入完成。

`CommonMobOracle.java` 使用实际 Skeleton/Spider/Cow/Sheep/SheepFur/AdultChicken/Enderman factories，单 worker BelowNormal JVM 导出七 rigs、21 小样本；没有压测或 GPU 进程。数据算法对照通过，最大 pose 误差 `1.26e−7`、顶点误差 `5.27e−5 cm`、法线误差 `1.19e−7`。

## 未实现项

弓和盔甲/持有物层，牛羊鸡幼年/其他气候（之前猪的变种已经实现），dyed/Jeb 羊毛颜色材质，eyes additive 材质和最终 glow，末影人搬运方块几何，runtime native attach/update 以及实机图形验收。

所有 Minecraft 皮肤/模型转换资源只能留本地私有输出，公开分发只含源代码和导入器。最终 snapshot/hash 见 `READY-v3.json`。保持 night_low_power、正式服 OFF、无 GUI/RPC/启停租约。
