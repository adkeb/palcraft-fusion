# 开发状态与原验收范围

本项目仍在开发，当前公开源码和实验包尚未完成全部 42 项游戏内验收。编译成功、身份登记或世界快照 ACK 各自证明一段流程，不代表完整可玩。

## 当前实际环境

2026-10-07 的验证环境为 macOS、CrossOver、Steam 离线《幻兽帕鲁》单机，以及本地 Minecraft/Fabric 后端。测试使用独立安装、独立 bottle 和既有测试世界；正式服关闭，原 Steam 安装和正式存档保留。

候选 19 的已完成运行：实际正常升级、冷启动、离线单机原世界加载、身份登记验签和原同一监督器的六组件接入已完成。初始 MC 世界 ACK 自然完成，场景提交与可信姿态同步开始工作；MC 坐标实际跟随 Pal 的真实存档出生位置，既有四项物品记录保留。日间目标帧率上限为 Pal60、MC60、HUD30；上限读回不代表真实帧率。一次物理 F5 已真实切入第一人称并显示 MC HUD，原角色、工具和原 HUD 隐藏。持续形态、移动、完整生存操作、性能和正常退出仍未验收。

候选 14 曾完成初始世界 ACK。该轮通过原变身接口进入第一人称时，真实引擎画面与原生状态共同证明角色、工具和原 HUD 隐藏；这是已结束运行的历史证据，不能当作当前候选的物理 F5 验收。

该轮随后发生正常死亡与复活，原 33 级角色、既有 MC 生命值和四项物品记录保留，但新视图仍等待 ACK。一次正常保存已完成，客户端在返回标题观察阶段发生访问异常、退出码 3，未完成正常退出。原客户端、后端和监督器已实际结束；[已保存崩溃恢复](../workstreams/saved-crash-off-recovery) 在真实安装成功签发独立收据，保留原 failed 状态、异常退出码和标题退出未完成事实。没有把该结果记为正常退出成功。

候选 15 未安装。候选 16 已实际更新，但原生初始化卡住；仅测试用 CrossOver 容器的运行会话重置后，客户端很早以退出码 53 结束。候选 17 的 [可选原生启动日志](../workstreams/native-menu-loader-diagnostics) 捕获了真正新日志，提示 Steam API 找不到正在运行的 Steam。恢复测试容器中已有的离线 Steam 后，原生初始化、Mod 加载和正常世界流程实际成功。原 Steam 容器和私人存档保留，日志没有公开。未把退出码 53 直接解释为 DLL 缺失。

候选 18 的初始覆盖请求误以 MC 旧坐标为中心，使所需半径超出原容量；候选 19 的 [完整目标区域同步](../workstreams/target-ring-centre) 改为认证目标区域的中心，保留完整覆盖和原预算，已在实际接入中完成 ACK。候选 18 的正常保存之后还有真实游戏晚写，随后返回标题发生退出码 3 的异常。原 finalizer 先正确拒绝变化的见证；[晚写崩溃收尾](../workstreams/late-saved-crash-final-observation) 在原早期见证旁增加标准 codec 实际解析后的最终观察，完成独立 crash-off 收据和正常候选 19 更新。未将异常退出记作正常成功。候选 19 的 [暂停旧世界回调](../workstreams/paused-native-title-lifecycle) 正常退出效果仍待验证。

候选 11 曾完成实际世界 ACK 和 readiness，随后正常保存、返回标题、退出并实际等待后端结束。新增 [正常退出收尾入口](../workstreams/normal-stop-off-finalize) 已在真实安装成功补完原一次性收尾，339 份持久文件 stat/SHA 和事件卷身份一致。该轮 ACK 与 ready 是已结束运行的历史证据，不能复用于候选 13。[自动收尾增量](../workstreams/normal-coldboot-auto-finalize) 已随候选 13 安装，针对性测试通过；缺失收据时的自动启动分支仍待实机验证。

候选 12 的更新曾将三份正常生成的配置误判为冲突。候选 13 包含 [正常生成配置的事务修复](../workstreams/normal-standalone-generated-ownership)，并已成功完成真实更新与原日志分卷；没有手动改写安装文件归属哈希。针对性测试覆盖正常采纳、错误拒绝、回滚和第二周期。

候选 19 的正常保存、世界清理、返回标题与退出已实际成功，原客户端/原生进程退出码0，六组件等待完成并离线；原正常 finalizer 签发了 quiet-off 收据，没有采用强制或崩溃恢复。候选 21 随后通过正常更新与冷启动，补齐两项既有单机材料兑换 Python 接口并安装原生诊断；完整兑换仍缺少付费容器登记与持久 watcher，未宣称成功。

候选 21 初次场景准备超时，但完整81个目标快照已接受；原同一旅行重试一次后自然完成。F5、同界面煤整栈移动与2×2火把合成实际发生：煤7→6、木棍2→1、火把增加4，木镐保持1，没有直接改库存。挖掘拾取、持续形态和完整库存/箱子持久仍在验收。原生诊断实证一次模式退出由camera_inactive触发，连接/generation稳定且没有F5/ESC或暂停；当前重新获取的相机已正常。未将当前相机age当作历史退出瞬间的数据。

## 当前问题与下一步

[第一阶段修正](../workstreams/standalone-realm-cadence)、[直接获取本地控制器与帧内复用](../workstreams/standalone-native-controller-cadence) 和 [同回调静态检查优化](../workstreams/standalone-callback-live-guard) 已进入当前候选。候选 17 完整负载的三个短样本回调均值为 134.5、140.6、135.9 毫秒，仍约 7 FPS。其 discovery 统计包含完整权威调度器，不能只据这个字段归因于控制器发现。

已确认保存服务在同一次回调重复执行控制器扫描、权威读取和原生身份写盘。[帧内服务复用](../workstreams/standalone-service-frame-reuse) 已合入候选 18，保留真实 UID、世界、原生进程与原新鲜度条件。源码检查只证明重复工作减少，当前候选的真实帧率提升尚待验证。原生代码的完整游戏文件散列只在首次调用执行，持续性能问题不能归因于每秒重算整份游戏文件。原生侧 750 毫秒新鲜度要求保持不变。

候选 13 的角色曾偏离已提交落点约 149 厘米，初始场景切换失败。[冻结锁保持修复](../workstreams/travel-owned-hold-maintenance) 已进入候选 14，该轮初始切换完成 ACK，未更改落点、容差或 ACK。正常复活后的新视图仍未完成 ACK；候选 16 的 [单机复活生命周期修复](../workstreams/standalone-respawn-lifecycle) 在原上下文暂不可用时保留下一回调重连路径，并清理已正常停止的旧共享视图归属，真实复活恢复仍待验证。

候选 17 已从 HUD 的真实进程环境确认：[前台归属组](../workstreams/mac-owned-foreground-group) 和 [启动阶段修复](../workstreams/mac-hud-normal-starting-phase) 实际生成了正确的游戏与启动助手归属组。正常激活已运行的游戏助手后，原平台焦点自然变为 1，原生输入视口恢复为 1280×720；没有改写焦点文件或另起游戏。计算机使用工具绑定仍超时，现有 macOS 键盘权限允许实际 HID 按键，但一次 F5 发送后形态未切换，尚不能证明原生入口收到了该键。候选 19 通过真实桌面像素定位被遮挡的标题栏，普通点击将真正游戏窗口置前后，一次 OS F5 实际触发变身，原生记录与第一人称 HUD 图像对应。之后发生自动断线、切回与重新接入；新视图 ACK 自然恢复，但持续输入和完整生存操作仍待验证。

候选 17 的初始接入选择了 MC 旧存档的位置，原 PalUtility 碰撞检查拒绝传送。真实地形读取确认目标脚点与 Landscape 重叠；原角色正常存档位置却已可用。[初始 NativeHome 修复](../workstreams/initial-native-home-pal-spawn) 让这一分支保留已认证的真实 Pal 出生位置，并据实际脚点重算覆盖，完整碰撞、提交、相机与 ACK 流程及 50 厘米容差保留。MC 通过原来只在 ACK 后开放的可信姿态同步跟随同一角色，辅助维度旅行不变。候选 19 实际完成初始 ACK 和可信姿态跟随，原生角色没有为此执行额外传送；其余维度与完整移动仍待验证。

[原启动阶段后端准备](../workstreams/normal-bootstrap-managed-backend-prepare) 已实际通过原生产入口更新三个受管 MC 副本，再由原监督器启动六组件；未启动第二个游戏、伪造归属散列或改写世界。该增量已与晚写收尾合入源码审核通过的候选 20，实际普通安装与重新接入仍待执行。

[定时画质接口修复](../workstreams/power-profile-observed-api) 已公开。日间游戏帧率上限的设置读回不等于真实达到该帧率；夜间低功耗仍须遵守当前用户配置和实际温度。

通过 [原生诊断完整源码入口](../workstreams/native-mode-off-diagnostics) 已重新编译四个单元，没有使用旧项目对象。AMD64、导入和导出一致，代码/只读数据等段一致，构建标识段不同；这个新编译副本尚未加载到游戏。

一次 [细分功能计时](../workstreams/feature-worker-timing-observer) 已还原全部包装，全局 GameStateBase、PalPlayerController、PalCharacter 对象扫描占主要时间。此前把重复权限验证当作主要热点的假设已被 aggregate 测量排除，未采用五处相应清理草案来宣称帧率改善。

## 构建与交付

既有 AI 生存建造、基地管理、材料消费、箱子合并分类源码，与原生桥接、安装器、MCP 和当前功能候选均已公开。各独立源码增量保留适用基线与验证范围。Windows ShellLink 标准库备选只完成格式与合成输入检查，尚未证明实际 vendor parser 成功。

MC 10.7 复活同步候选已通过 Java 25 编译并在隔离环境加载。公开 [完整 MC 源码构建入口](../player-standalone/full-mc-source/BUILD.zh-CN.md) 已从 100 个生产源生成 168 个新 class，按记录的混合 debug 与行号元数据规范重建基础包，再衔接六源增量得到相同 10.7 产物；未复用旧项目 class 字节。全项目 Gradle 构建、其他用户全新环境、完整库存持久与游戏验收仍待验证。[MC 10.9 组件对与完整源码](https://github.com/adkeb/palcraft-fusion/releases/tag/v0.2.0-integration.10.9-center-source) 已公开，保留原源码内容和许可证。[实验发布包](https://github.com/adkeb/palcraft-fusion/releases) 保持实验标记；MC 10.8 伤害特性包不代表本轮运行已采用或验收。

[当前错误与历史拒绝状态修正](../workstreams/session-proxy-current-error-status) 已公开，避免把已恢复后的旧错误展示成当前失败；仅为状态字段候选，尚未安装。

## 原 42 项要求

| 范围 | 项数 | 要求 |
| --- | ---: | --- |
| 环境与生存规则 S01–S02 | 2 | 隔离测试、保留原数据、科技与材料成本、静音 |
| 角色与控制 F01–F06 | 6 | 变身、切回、自然移动、工具隐藏、失焦释放、共享生命与死亡 |
| 世界与视觉 W01–W06 | 6 | 固定世界坐标、纹理与模型、实心碰撞、复杂方块、指引、动画 |
| 生存与库存 I01–I08 | 8 | 背包、放置、挖掘、拾取、合成、烧炼、兑换、箱子持久 |
| 多人 M01–M03 | 3 | 身份和输入独立、共享世界竞争取物、会话隔离 |
| 恢复与稳定 R01–R04 | 4 | 重连、恰好一次事务、持续稳定、冷加载与卸载 |
| 性能 P01–P02 | 2 | 实际帧耗时与延迟、规模化世界有界调度 |
| 玩家交付 D01–D04 | 4 | 可配置安装、连接反馈、保存档卸载、可复现当前构建 |
| 世界扩展 X01–X06 | 6 | 流体、红石、作物、维度、实体战斗、投射物与爆炸 |
| AI 整合 A01 | 1 | 既有建筑、科技、材料、基地和仓储能力保留 |

源码候选、数值测试、真实引擎行为、实际图像和多人测试各有不同范围。未完成项保持未完成；该表不是 42 项全部通过的声明。

新候选 22 已合入 [持续变身选择](../workstreams/native-camera-stall-form-intent)、[有限快照准备进度](../workstreams/initial-target-snapshot-progress-lease) 和 [单机上下文扫描复用](../workstreams/standalone-global-context-scan-reuse)。当前尚未安装：候选 21 在正常采掘一根火把后发生真实原生访问异常，MC 权威记录确认方块移除，但原生清理、掉落拾取和保存结果未验收；正在定位并保留异常退出事实。

[材质资源生命周期修复](../workstreams/material-resource-lifetime) 与 [未保存崩溃收尾](../workstreams/unsaved-owned-crash-off-recovery) 已公开。实际收尾明确未完成保存并保留原失败记录；原更新保留 Saved，随后发现并修复崩溃 XML 编码与启动收据分支问题。新候选 25 已完成源包审核，游戏内重新采掘拾取和性能效果仍待验证。

候选 26 已完成正常更新、离线单机原世界加载和同一监督器的六组件接入，受管纹理目录错误已消失。当前场景准备因炉子的方块实体元数据与动画 clip 判断混用而受阻；已公开 [静态方块实体模型修复](../workstreams/static-perblock-model-without-clip)，保留完整模型和箱子的原动画。3 项限定源码案例通过，实际新候选场景 ACK、挖掘拾取和性能仍待验证。

正常退出时的晚写存档收尾已实际成功：[正常晚写存档观察](../workstreams/normal-late-game-save-observation) 保留早期保存记录，原标准 codec 重新检查最终 Level、Player 与本人 UID；游戏和六组件的真实退出记录均保留。候选 28 已正常更新、保留存档并重新启动离线单机，完整场景与生存玩法仍在验收。公共安装的 codec 依赖配置尚未全部解决。

[可选标准存档 codec 入口](../workstreams/portable-normal-codec-entry) 增加 `finalize-stop --codec-python`，缺少 pyooz 时提供明确提示；三项限定函数案例通过，目前为未安装的源码增量。

[同一运行会话内调整性能](../workstreams/live-owned-power-profile) 和 [实际读回关联修正](../workstreams/live-power-readback-correlation) 已公开源码：以后可由原监督器在线调整帕鲁、MC 与 HUD 帧率并读取实际值，避免仅修改下次启动配置。MC/Swift 编译通过，当前游戏尚未安装这项增量，实际实时效果仍待验证。

Mac 候选 28 已实际完成首次自然场景 ACK 和物理 F5 第一人称变身，普通移动及快捷栏选择成功。鼠标转向和完整场景性能仍未达标；已公开 [CrossOver 鼠标消息兼容](../workstreams/mac-mouse-message-compat) 与 [碰撞回调内身份复用](../workstreams/collision-callback-realm-reuse) 源码候选，实际新版本效果待验证。

候选 29 的物理 F5、普通鼠标转向、火把放置→挖掘→拾取（3→2→3）和背包内移煤已实测发生，原生火把模型像素仍未确认。在线性能读回少了 relay 一项，原因是旧启动模板仍选择外部旧脚本；[受管 relay 入口选择修复](../workstreams/managed-relay-entry-selection) 已公开源码，真实新版本效果待验证。
