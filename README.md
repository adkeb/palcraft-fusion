# PalCraft Fusion

《幻兽帕鲁》× Minecraft 联动，以及供 AI 使用的基地建造、管理、仓储和 MCP 工具。

本仓库公开开发源码、原生桥接、构建与资产生成工具、安装器、实验候选和验证代码。项目仍在开发，**当前版本尚未达到完整可玩验收**。

## 当前状态

截至 2026-10-07，开发环境为 macOS、CrossOver、《幻兽帕鲁》Steam 离线单机和本地 Minecraft 后端。既有 AI 生存建造、基地管理和箱子整理代码，以及跨游戏原生桥接、安装器和 MCP 工具均已公开。

候选 14 已在实际 Mac 上完成正常更新、冷启动、原世界加载、新身份登记验签和同一监督器下的六组件接入。初始世界 ACK 自然完成；通过原变身接口进入第一人称时，实际引擎画面中原角色与工具已隐藏。这些证据尚不覆盖物理 F5、前台 HUD 和完整生存玩法，见 [开发状态](docs/STATUS.md)。

最新修正源码分别保存在 [玩家保存与重启流程](workstreams/normal-journal-owned-player-flow-v2)、[原生实体身份绑定](workstreams/native-entity-binding-next)、[MCP 身份观察](workstreams/MC-local-scope-observation-next) 和 [Windows 快捷方式生成备选](workstreams/windows-shelllink-stdlib-alternative)。备选只有格式与源码检查，尚未证明实际 vendor 解析成功。

候选 14 的正常复活已恢复原 33 级角色，但后续世界 ACK 未完成，完整负载下仍约 6 FPS。随后的一次正常保存已完成，客户端在返回标题期间以退出码 3 崩溃。[已保存崩溃恢复](workstreams/saved-crash-off-recovery) 已在真实安装签发独立收据，保留异常退出事实；后续更新已实际保留存档。

候选 16 还包含 [帧内检查优化](workstreams/standalone-callback-live-guard)、[HUD 启动阶段归属修复](workstreams/mac-hud-normal-starting-phase) 和 [单机复活生命周期修复](workstreams/standalone-respawn-lifecycle)。这些修正已通过各自针对性源码检查，完整实机效果仍待验证。

候选 17 已在真实 Mac 上恢复离线 Steam 前置，完成正常世界加载、身份登记验签和六组件接入。HUD 的启动归属组已实际生成，正常切换游戏到前台后，输入焦点和 1280×720 视口也恢复；完整负载仍约 7 FPS，F5 事件发送尚未证明游戏变身。初始接入还在把原角色移向 MC 旧位置，目标与真实地形重叠。[保留真实 Pal 出生位置](workstreams/initial-native-home-pal-spawn) 与 [删除重复身份检查及写盘](workstreams/standalone-service-frame-reuse) 已合入候选 18，等待正常升级后的实机验收。

已有 [正常退出收尾源码](workstreams/normal-stop-off-finalize)、[上下文发现性能修正](workstreams/standalone-realm-cadence) 和 [定时画质接口修正](workstreams/power-profile-observed-api)，每项均标明源码检查与实机验证范围。

MC 10.7 复活同步与 macOS 13 ARM64 HUD 已提供 [实验发布包](https://github.com/adkeb/palcraft-fusion/releases)。MC 完整 100 生产源已通过 [整合源码构建入口](player-standalone/full-mc-source/BUILD.zh-CN.md) 重建基础包，再衔接六源增量得到相同的 10.7 产物；历史混合 debug 策略公开记录，未使用旧项目 class。其他用户的全新环境与完整游戏验收仍待验证。

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
