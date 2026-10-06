# PalCraft Fusion

《幻兽帕鲁》× Minecraft 联动，以及供 AI 使用的基地建造、管理、仓储和 MCP 工具。

本仓库公开开发源码、原生桥接、构建与资产生成工具、安装器、实验候选和验证代码。项目仍在开发，**当前版本尚未达到完整可玩验收**。

## 当前状态

当前开发环境是 macOS、CrossOver、《幻兽帕鲁》Steam 离线单机和本地 Minecraft 后端。正常单机角色、基地归属与 MC 玩家身份的恢复已经实际运行；日志分卷已解决旧事件历史重放的问题。

真实世界快照已发布，模型和碰撞已有提交。一次真实连接已完成原生世界确认，并实际导出、编码和解码 MC HUD 像素；导出图像显示的是原版死亡界面，尚未证明 HUD 已显示在前台帕鲁窗口中。隔离测试角色已通过正常复活流程返回存活状态。

最新 G/S 配对候选已通过原安装器正常更新和重载。该次新会话的完整目标模型与碰撞提交已经完成，收到本次最终世界 ACK；最初认证短暂不可用仍需要一次原 retry。当前继续核对新图像、复活同步、变身、实际输入和完整生存流程。此结果不等于物理画面、碰撞或全部游戏功能通过，见 [本次运行范围](docs/evidence/GS-current-original-full-target-ACK.json)。

10.7 复活同步候选已修正六个 Java 文件并编译通过，已在隔离单机环境加载；完整复活同步与游玩仍待验收。正常帕鲁复活后，MC 沿原版流程替换死亡角色，并保留同一连接的身份和已有头像数据。见 [源码来源记录](docs/evidence/respawn-sync-source-manifest.json)。

最新安装器补齐真实会话和告示牌模块，并提供公开 macOS 13 HUD 的组合规格。稀疏区段调度与有界任务状态字段已经进入当前客户端源码，其独立差异见 [调度候选记录](workstreams/chunk-sparse-yield-next/README.md)。这次完整准备和 ACK 已通过，持续性能及完整游玩仍待验收。

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
