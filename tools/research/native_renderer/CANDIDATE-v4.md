原生渲染候选 v4 / 世界碰撞伴随模块 v8

本候选未部署、未在真实 Unreal 中验收。Mac 当前保留已验收的 native v3 / companion v7；稳定副本在同目录 stable-v3，源/DLL/脚本散列在 SHA256.json。正式服未操作，Mac 图形/RPC/客户端启停租约已交还主负责人。夜间低功耗阶段只继续轻量源码接线，不新增压测或图形进程。

已实测的 v3 范围：28 个固定世界原生模型，35 sections / 760 vertices / 1140 indices；6 次 replay 与 6 圈视角，未新增 crash；真实走动及 58 actors 的 water channels 14/19/25 全为 Ignore，visual NoCollision、physical QueryAndPhysics。按钮正常生存库存 1→0→掉落1→走动拾取1，服务端一致；旧生产端将无碰撞按钮输出成 clear，按钮原生视觉失败，不能称全部玩法通过。F5 已退出并恢复原角色/视角/移动与视角输入。原始证据在 coordination/native_renderer.json；QA runs/native-v3 中的附件显式标 historical。

v4 已实现：PALCPRC4，184 字节头（context + 17 reflected addresses / ProcessEvent 总共18个I8，位置3个double，section数和flags两个I4），flag1 在组件注册前隐藏 Actor。native 读取、验证所有几何后才分配 actor；各 section 上限65536顶点/262144索引、整体256 sections；校验有限坐标/法线/UV和索引，生成每顶点 UV tangent，white FColor，visual NoCollision/IgnoreAll/NoOverlap。deferred AddComponent，完整 section/material 后 FinishAddComponent 一次注册。

Lua 接口：

- models.spawn(ctx,origin,geometry,x,y,z,options) 保持数字 actor/component 返回值。
- models.spawn_groups(ctx,origin,groups,at,options) 接已分组几何；options.hidden 可隐藏准备，origin.y_origin 默认64。
- models.prepare(ctx,origin,batch) batch={groups,at,revision,generation?,fence={world_session,dim,view,mapping}}；返回 prepared handle（actor/component/revision/generation/fence/state/native_registered）。world_session/dim/mapping 是非空字符串，view 是非负整数。
- models.commit_transaction(newVisual[],oldVisual[],collision?) 全部新页必须相同 fence/revision，旧页必须 active。collision={adapter,prepared[],previous[],expected_fence?}，先检验全部视觉 handle，再 collider preflight/commit，再同一游戏 tick 显新隐旧并释放旧 actor。new=[] 支持卸载。只有 handler 完成注册的事实，不能替代渲染或物理实机验收。
- commit、discard、unload 支持单 handle/数组；reset(newGeneration,contextAlive) 在 world 已销毁时只丢弃 handle，避免解引用旧 UObject。
- set_material_provider(resolve(ctx,g,assetRoot),verifiedCapabilities) 返回 UObject 或 {material,texture,...}；保留资源生命周期，能力由真实验证后显式开启。

model-assets.json 可原子选择独立冻结目录 models-v2/v3/v4-<hash>；provider_version 为2或3，v3/v4资产默认用 geometry v3。必须一起安装所选 provider 的依赖，不能拷读中的可变资源树。几何缓存只读。

companion v8 是唯一世界 journal reader：World.new(auto_view=false)，v2 ops 优先，legacy_after_v2 忽略，坐标 coalesce，空 boxes 保持0碰撞，visible=false 不造外观；快照结束才发布完整 region。读文件有单次256KiB上限，EOF继续。M.world / M.models / M.context / M.set_view 可接 runtime。M.set_world_observer({on_row(row,accepted,reason,M),on_lifecycle(event,fullRow,M),tick(M)}) 只通知已有 reader。observer 异常独立 status，不能用 pending==0 冒充快照覆盖与真正 readiness。MC 维度事件只记 pending_view，真实 host 位移由 dimension_travel owner 处理。

compound碰撞、chunk scheduler/adapter 由 chunk_scaling 提供；server实体只由 server/features 初始化，不能在伴随模块重复 hook。材质、实际流体物理、动画继续由对应 owner 接线。当前已验证能力默认 onlyopaque，cutout/translucent/tint/animation/dynamic/compound runtime 验收仍 false；需要这些能力的 chunk 准备会明确拒绝。

离线验证：native 17 contract cases（ASan/UBSan，含真实 Lua 写出的184字节包读取）、Lua model adapter 18 cases、companion world glue 16 checks。Windows x64 DLL 已交叉编译。后续真实运行候选须由当前独占租约 owner 完成，world v2 生产端与消费者必须同一候选交付。
