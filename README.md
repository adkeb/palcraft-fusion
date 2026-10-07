# PalCraft Fusion

《幻兽帕鲁》× Minecraft 联动，以及供 AI 使用的基地建造、管理、仓储和 MCP 工具。

本仓库公开开发源码、原生桥接、构建与资产生成工具、安装器、实验候选和验证代码。项目仍在开发，**当前版本尚未达到完整可玩验收**。

## 当前状态

截至 2026-10-07，开发环境为 macOS、CrossOver、《幻兽帕鲁》Steam 离线单机和本地 Minecraft 后端。既有 AI 生存建造、基地管理和箱子整理代码，以及跨游戏原生桥接、安装器和 MCP 工具均已公开。

候选 19 已在真实 Mac 上完成正常升级、离线单机原世界加载、身份登记验签和同一监督器下的六组件接入。初始世界 ACK 已自然完成；MC 通过原可信姿态同步跟随 Pal 的真实存档出生位置，未移动原角色来绕过地形检查。既有物品记录保留，详见 [开发状态](docs/STATUS.md)。

最新源码包括 [完整目标区域同步](workstreams/target-ring-centre)、[保留真实 Pal 出生位置](workstreams/initial-native-home-pal-spawn)、[帧内服务复用](workstreams/standalone-service-frame-reuse) 和 [返回标题时暂停旧世界回调](workstreams/paused-native-title-lifecycle)。一次真实前台 F5 已切入第一人称，实际 MC HUD 可见；持续输入、完整生存操作、实际性能及正常退出仍在验收，项目没有宣称完整可玩。

今天另公开 [晚写存档的崩溃收尾](workstreams/late-saved-crash-final-observation) 和 [原启动阶段的受管后端准备](workstreams/normal-bootstrap-managed-backend-prepare)。两项已在独立测试安装执行，分别保留真实异常退出事实并完成后续正常升级，以及通过原生产入口更新三个后端副本；已整合成源码审核通过的候选 20，实际普通更新尚待执行。

候选 21 已正常升级并加载原离线世界；一次目标准备超时经原恢复入口完成。真实 F5、背包内整栈移动、2×2 火把合成已获得本机输入和库存证据；持续形态仍受临时相机失活影响，当前完整负载的性能尚未达标。候选 19 的新世界清理与暂停逻辑已实际完成正常保存、标题退出和六组件结束。

[原生模式退出诊断](workstreams/native-mode-off-diagnostics) 已公开18个源/头文件和从源码构建入口。新鲜编译四个单元得到同样的导入、导出和代码段，构建标识段与原编译产物不同；不宣称整文件同哈希。两个[回调计时工具](workstreams/callback-timing-observer)和[功能计时工具](workstreams/feature-worker-timing-observer)已完成短实测并还原；当前主要热点是全局对象扫描。

已有 [正常退出收尾源码](workstreams/normal-stop-off-finalize)、[上下文发现性能修正](workstreams/standalone-realm-cadence) 和 [定时画质接口修正](workstreams/power-profile-observed-api)，每项均标明源码检查与实机验证范围。

MC 10.9 目标区域同步已提供 [组件实验包](https://github.com/adkeb/palcraft-fusion/releases/tag/v0.2.0-integration.10.9-center-source)；MC 10.7 复活同步与 macOS 13 ARM64 HUD 已提供 [实验发布包](https://github.com/adkeb/palcraft-fusion/releases)。MC 完整 100 生产源已通过 [整合源码构建入口](player-standalone/full-mc-source/BUILD.zh-CN.md) 重建基础包，再衔接六源增量得到相同的 10.7 产物；历史混合 debug 策略公开记录，未使用旧项目 class。其他用户的全新环境与完整游戏验收仍待验证。

## 源码地图

| 目录 | 内容 |
| --- | --- |
| `palcraft/client`、`palcraft/server` | 当前 Lua 客户端与权威侧组合、模型、碰撞、物品、实体、流体、维度与角色控制 |
| `palcraft/mc` | Minecraft/Fabric Java 联动模块，10.6 基础与 10.7 复活同步候选 |
| `palcraft/native`、`palcraft/render` | 原生 Unreal 网格、碰撞、输入、相机、材质、共享帧和桥接代码 |
| `palcraft/mcp` | AI 基地与仓储工具、MC 控制工具及本地队列适配器 |
| `palcraft/installer`、`palcraft/launcher` | 可配置路径的安装、启动、会话、恢复与卸载实现 |
| `mac` | macOS HUD、跨平台帧传输和本地后端脚本 |
| `palworld-live`、`palworld` | 独立 AI 建造、基地管理、材料消费和箱子合并整理源码 |
| `modules`、`workstreams`、`experimental` | 独立功能候选与原生、材质、实体、维度和事务增量 |
| `palcraft/tests` 及各模块 `tests` | 现有针对性测试与验证工具 |
| `tools/legacy` | 历史作者工具，供追溯；不是当前启动入口 |

详见 [构建说明](docs/BUILD.md)、[状态与验收范围](docs/STATUS.md) 和 [第三方说明](THIRD_PARTY.md)。

## 使用与资源

需要自行提供合法安装的游戏、CrossOver 和对应的 Java/Fabric 依赖。本仓库不提供商用游戏文件、提取的纹理或模型；使用源码中的提取、转换与生成工具在自己的本机生成所需资源。

个人存档、世界、账号凭据、私钥、运行队列、交易 WAL 和个人测试快照不属于公共发布内容。公共配置中的路径和身份是占位参数，必须通过自己的正常加载、发现、观察与登记流程生成。

基地建造采用正常生存规则：遵守科技与材料成本。仓储操作沿原物品系统执行，不能通过复制原始存档来假装在线操作成功。

## 许可

作者扩展沿用 MIT 许可，第三方代码与接口保留原许可和说明。Minecraft、Palworld、CrossOver 及 Unreal 的商用文件不在该许可授予范围内。见 [LICENSE](LICENSE) 和 [THIRD_PARTY.md](THIRD_PARTY.md)。

新候选 22 已合入 [持续变身选择](workstreams/native-camera-stall-form-intent)、[有限快照准备进度](workstreams/initial-target-snapshot-progress-lease) 和 [单机上下文扫描复用](workstreams/standalone-global-context-scan-reuse)。当前尚未安装：候选 21 在正常采掘一根火把后发生真实原生访问异常，MC 权威记录确认方块移除，但原生清理、掉落拾取和保存结果未验收；正在定位并保留异常退出事实。

[材质资源生命周期修复](workstreams/material-resource-lifetime) 与 [未保存崩溃收尾](workstreams/unsaved-owned-crash-off-recovery) 已公开。实际收尾明确未完成保存并保留原失败记录；原更新保留 Saved，随后发现并修复崩溃 XML 编码与启动收据分支问题。新候选 25 已完成源包审核，游戏内重新采掘拾取和性能效果仍待验证。

候选 26 已完成正常更新、离线单机原世界加载和同一监督器的六组件接入，受管纹理目录错误已消失。当前场景准备因炉子的方块实体元数据与动画 clip 判断混用而受阻；已公开 [静态方块实体模型修复](workstreams/static-perblock-model-without-clip)，保留完整模型和箱子的原动画。3 项限定源码案例通过，实际新候选场景 ACK、挖掘拾取和性能仍待验证。

正常退出时的晚写存档收尾已实际成功：[正常晚写存档观察](workstreams/normal-late-game-save-observation) 保留早期保存记录，原标准 codec 重新检查最终 Level、Player 与本人 UID；游戏和六组件的真实退出记录均保留。候选 28 已正常更新、保留存档并重新启动离线单机，完整场景与生存玩法仍在验收。公共安装的 codec 依赖配置尚未全部解决。

[可选标准存档 codec 入口](workstreams/portable-normal-codec-entry) 增加 `finalize-stop --codec-python`，缺少 pyooz 时提供明确提示；三项限定函数案例通过，目前为未安装的源码增量。

[同一运行会话内调整性能](workstreams/live-owned-power-profile) 和 [实际读回关联修正](workstreams/live-power-readback-correlation) 已公开源码：以后可由原监督器在线调整帕鲁、MC 与 HUD 帧率并读取实际值，避免仅修改下次启动配置。MC/Swift 编译通过，当前游戏尚未安装这项增量，实际实时效果仍待验证。

Mac 候选 28 已实际完成首次自然场景 ACK 和物理 F5 第一人称变身，普通移动及快捷栏选择成功。鼠标转向和完整场景性能仍未达标；已公开 [CrossOver 鼠标消息兼容](workstreams/mac-mouse-message-compat) 与 [碰撞回调内身份复用](workstreams/collision-callback-realm-reuse) 源码候选，实际新版本效果待验证。

候选 29 的物理 F5、普通鼠标转向、火把放置→挖掘→拾取（3→2→3）和背包内移煤已实测发生，原生火把模型像素仍未确认。在线性能读回少了 relay 一项，原因是旧启动模板仍选择外部旧脚本；[受管 relay 入口选择修复](workstreams/managed-relay-entry-selection) 已公开源码，真实新版本效果待验证。

候选 29 已实际完成鼠标转向和一次火把生存守恒，但正常死亡复活后的视图转换及返回标题未通过：保存完成后，返回标题发生真实异常退出。已公开 [暂时缺少保存证明时暂停](workstreams/transient-owned-world-proof-pause)、[等待原物理视图转换](workstreams/respawn-physical-transition-home-init) 和 [同世界复活保留帕鲁出生位置](workstreams/respawn-current-native-home) 源码候选；这不是完整复活或退出成功的声明。

候选 29 返回标题的异常退出已通过原已保存崩溃收尾实际恢复，保留退出码 3、标题未完成和原早期保存记录；最终存档经标准 codec 解析。新增 [正常已保存世界关闭](workstreams/normal-saved-world-shutdown) 源码保留原 operator guard，单独清理属于本次保存的恢复场景，再返回标题。限定源码检查通过，实际正常退出仍待下一版验证。

候选 31 已通过一次原恢复入口完成当前完整目标区域和 ACK；正常帕鲁复活后新视图也自然完成，MC 生命和原库存恢复，物理 F5 切回显示原装备与 HUD。首次自动准备仍有晚接入快照丢失问题，已公开 [权威快照晚接入补齐源码](workstreams/late-authoritative-snapshot-native-catchup)；自动冷启动、原生模型像素和正常退出仍未全部验收。

候选 31 已实测完成正常保存、返回标题、客户端/Host 退出码 0 与六组件退出等待；首次收尾仍待短暂端口释放后由原 finalizer 完成。背包 GUI 合成火把实际守恒（火把 3→7、煤 6→5、木棍 1→0），在线夜间帧率调整获得帕鲁、MC、HUD 和 relay 四项真实读回。原生模型可见性、箱子交互、自动首次同步、连续鼠标转向及完整 42 项仍未全部验收。

普通鼠标在窗口边缘停止转向的问题已形成 [Mac 归属光标捕获源码候选](workstreams/mac-owned-host-cursor-capture)：沿现有 HUD 回调确认实际 Mac 光标回中，再按真实进程、会话与视口同步 native 基线，保留菜单、失焦、按钮和 RAW 输入规则。限定源码案例及编译通过，实际无限转向和箱子模型交互仍待候选 32 验证。
