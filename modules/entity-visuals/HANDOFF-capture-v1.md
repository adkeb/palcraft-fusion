# 通用原版实体 Renderer Capture V1

此候选解决 MC 生物外形依赖手写 rig 清单的问题。独立 owned source，不改 next9/9.1、native公共renderer、EntityV3 或任何 frozen source/data；不增加授权协议或长驻服务。

## 最小可编译入口

`java/VanillaEntityCapture.java` 已以实际 26.3 jar 编译，包名 `dev.rehan.passthrough.client.visual`。integration 可复制到原 MC client source 的同名包，在现有 guest 的 client/render thread 调用：

```java
Map<String,Object> frame = VanillaEntityCapture.entity(
    entity, partialTicks, cameraRenderState, 60_000);
```

该方法直接调用既有 `Minecraft.getInstance().getEntityRenderDispatcher().getRenderer(entity)`、原 `createRenderState(entity,partialTicks)`、`getRenderOffset()`、`EntityRenderer.submit()`。collector 不以 kind 决定模型。`submitModel` 触发实际 `model.setupAnim()` 和 `model.renderToBuffer()`，捕获真实 visible parts、全部父子姿态、UV、法线和每顶点 RGBA。`submitModelPart` 的原 interface default path 也可走相同捕获；`submitCustomGeometry` 调用原 CPU callback。

不要外起另一 Minecraft 或服务。由 existing authenticated client snapshot/visual cache 绑定该帧到同一 MC UUID 与权威 row；AI/位置/碰撞/伤害仍现接口。捕获帧只用于显示，不提升自己为世界 authority。

## 几何、贴图与 Native

`frame.batches` 保留 `source` class、`render_type_name`、真实 `textures` Sampler绑定 ID、`has_blending`、light/overlay、layer order 与原 primitive。vertex layout=`x,y,z,nx,ny,nz,u,v,r,g,b,a`，空间是 MC entity-position-relative 且原 renderer 方向/pose 已烘。

`lua/captured_entity_visuals.lua`：

```lua
Capture.configure({json=J,root=CAPTURE_RESOURCE_ROOT,
    resolve_texture=function(resourceId) ... end})
local groups,effects=Capture.geometry(authoritativeRow,frame)
```

输出兼容现 native动态mesh，UE cm=(MCx*100,−MCz*100,MCy*100)，无 world O/y−64 偏移。`native_actor_yaw=0`，不要再按 row.body_yaw 转一遍，和原 EntityV3 scalar provider 前+X 模式分开选择。保留 NoCollision/entity_visual、texture_path/material_root、vertex_colors、overlay/light 与 source rendertype。

Static PNG 用 `VanillaEntityCapture.exportTexture(resourceId,localResourceRoot)` 从现有资源包取得真实文件。UV 已经过原 UvMapping，不能先猜物品名称再换皮肤。动态 player skins 与生成 atlas 需要 texture-owner 的 CPU导出/atlas映射，资源缺失明确保留 diagnostics。

Native材质尚未验收每顶点颜色、eyes additive、透明层等，捕获有这些数据不等于游戏效果已显示。实际 `render_type_name` 应由material映射，eyes标 additive_material_required，不要用 Foliage/WPO假装最终皮肤。

## 实际证明

`RendererCaptureOracle.java` 在 standalone BelowNormal/single-core/256MiB JVM 执行了实际 `CreeperRenderer.submit` 与此前手写清单未覆盖的 `EnderDragonRenderer.submit`，两者走同一个 collector。

CPU oracle 为避开游戏/图形 context，只有测试夹具使用 Unsafe 创建 renderer 实例并注入实际 factory model/空 layers；生产捕获直接使用既有 dispatcher 的真实 renderer，不使用 Unsafe。model factories、renderstate、submit 方法与 vertex stream 均来自原版，而非手写 dragon cuboid。

- Creeper：144 vertices，真实 `entity/creeper/creeper.png`。
- Dragon：3120 vertices，原 `EnderDragonModel` 的 body+eyes 两次提交，真实 `enderdragon/dragon.png` 与 `dragon_eyes.png`。
- 2 条原 renderer case，3264 captured vertices，UE投影误差 0。打包类实际运行标记为 `dev.rehan.passthrough.client.visual.VanillaEntityCapture`，没有误用旧 default-package class。

没有真实游戏中的 capture hook/native attach/screenshot验收，没有新 guest/GPU/GUI/RPC，无大规模矩阵/压力测试。

## 当前版本具体限制

模型与 custom-geometry 提交路径可捕获；`submitItem/submitBlockModel/submitMovingBlock` 尚未实现解析。纯物品 billboard、被搬运 block、展示物等可能没有任何模型 batch，会明确报告原提交类型。name/text/shadow/leash/flame/particles 等同样报告，不冒称全部可见。

不是 EntityRenderer 无法通用捕获；限制是当前 adapter 未消费这些不同 submit payload，以及动态/atlas资源还需 CPU texture adapter。当前不添加第二大平台或白名单补丁，只由integration将最小方法接到现 guest，后续按真实 unsupported diagnostics 补必要路径。

资产来自用户安装版本，仅私有 root；public包只Java/Lua/导出器源码。最终 frozen/data/script hashes 在 `READY-capture-v1.json`，机器状态为 `coordination/model_geometry.json`。
