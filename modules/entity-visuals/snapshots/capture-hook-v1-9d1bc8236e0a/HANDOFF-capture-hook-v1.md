# Actual capture Hook → authenticated cache → native consumer

此增量完成实际调用端源码，不仅给静态 API。当前源码原本没有名为 visual_cache 的完整 event/op；我们明确新增派生显示缓存合同，复用 existing HostLink、SessionHandle、ClientBridge 已接受的 WorldView，不另造登录、权威协议或长驻服务。next9/9.2 运行与冻结保持不动。

## MC 实际调用端

`apply_capture_hook.py NEXT_MC_STAGING_ROOT` 将三个新 owned Java 文件复制到 integration-owned next source，同时做四处有界接线：

1. `PassthroughClient.onInitializeClient()` 调用 `EntityCaptureExporter.initialize()`。
2. mixins JSON 登记实际 `LevelRenderer.render TAIL` 注入，取得原 `CameraRenderState`，调用 `EntityCaptureExporter.frame()`。
3. `HostLink` 新 `entity_visual_view` operation 在 existing execute/lease/MCepoch guard 内调用 exporter.bind；发送用 existing `respond()`，仍由同一 host_session wrapper 绑定。
4. `SessionPolicy` 将该只读操作归入现有 world.read，不新 scope/登录。

此接线脚本已在仅四个既有源文件的私有 staging fixture 真正应用成功；没有修改当前共享MC运行source。实际 combined Java/Mixin 编译只由 integration 后续一次执行，本分支未单独编新 hook，更未启动第二 guest。

## Source、范围与状态

MC exporter 使用 `ClientBridge.trustedWorldView()` 的当前 applied tuple，比对 host request 的 mc_uuid/world_session/dim/view；mapping与exclusive bounds由已确认 native scope提供。GuestSession epoch/view改变或断连会停采样。依次捕获当前已加载、范围内最多64个近端实体，每原render frame最多2个，不提高游戏FPS。

同一实际 vanilla捕获：dispatcher renderer/createRenderState/getRenderOffset/submit → 原 model.renderToBuffer。每row稳定 `mc:<UUID>`，pose/UV/RGBA/法线已烘，仍world-origin-relative、不写位置/AI/碰撞/伤害。CPU proof沿用既有实际Creeper/Dragon narrowproof，不追加大矩阵。

缺 static PNG 会按 `resource_pack_png_missing` 报错；生成 atlas 则 `generated_atlas_cpu_export_missing`；dynamic skin缺CPU资源则 `dynamic_skin_cpu_resource_missing`，附原 resource ID。没有supported geometry会 `renderer_submitted_no_supported_geometry`；batch缺Sampler0明确记录。不把空白或资源缺依赖说成显示完成。

## 派生缓存 event

`entity_visual_asset`：同fence + producer/epoch/seq/created_ms，含resource、sha256、bytes、index/chunks、base64。原PNG通过同authenticated WS分块，接收端汇合、校验SHA256和PNG signature，再原子落本地 `<sha256>.png`。不假设Mac可读5090盘。

`entity_visual_cache`：同fence，complete替换rows。每row有id/dimension/captured_ms/available、actual frame、textures(resource→hash/size)、具体resource_errors/error。未采样实体数与budget_skipped_entities是明确诊断，不将预算截断伪称全部覆盖。

fence沿既有sign字段 `mc_uuid,world_session,dim,view,mapping`，HostLink respond继续添加existing `host_session`。不是第二个auth协议；客户端验证使用既有host-session callback。

## 实际 Native cache/read callbacks

`lua/entity_capture_cache.lua` 自带 actual packet accept/PNG assembly/cache/storage，输出 native已有consumer所需：

- `read_visual(authoritativeRow) -> frame,scope`
- `verify_visual(frame,scope,row,actualActor) -> true`，现auth/view/实体UUID/维度/pose freshness并保持exact Actor校验。
- `resolve_texture(resourceId) -> 已验证PNG路径`
- `tick_binding()` 通过已有 send_binding发送新只读view request。

`lua/capture_runtime_binding.lua` 具体组合 Cache + Captured provider + Native6 captured consumer，返回renderer供 existing exact observer、receive() 给同authenticated事件dispatch、tick()/stop() 管视图生命周期。RGBA保留于原frame与 `g.vertex_colors`，需native6真实72byte格式，不让旧whiteFColor冒称保真。

现rawWS消息可沿既有render worker事件journal进入runtime dispatcher。runtime owner把两个 derived event送 `binding.receive()`、原game-thread loop送 `binding.tick()`，exactentity observer使用 `binding.renderer`；这属于当前native公共owner接线，不在本分支改它的冻结文件。callback options的host/session与Actor verifier仍从已有认证/绑定取，不由显示缓存创建世界权威。

## 检查、编译与限制

只有一个小cache fixture：认证连接+view → PNG hash+base64落盘 → 实体read/verify，以及otherhost拒绝；SHA256两个标准向量。不是整套新增压力/MCoracle。PNG-root目录由runtime建立。

Hook Java与Mixin source已经实际接到source staging，尚待integration合包编译。Native6 consumer由native owner独立接线，真实shader颜色/eyes/透明层仍pending。已有capture-v1的 Item/Block/MovingBlock/Text/Shadow/Leash/Flame 等未消费类型诊断继续保留。

没有GUI/RPC/重启/第二guest/新服务，没有物品或HP/伤害权限写。夜间低功耗保持。final source increment root/hash见 `READY-capture-hook-v1.json`；public只source，不含MC原图。
