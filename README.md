# PalCraft Fusion

《幻兽帕鲁》× Minecraft 联动，以及供 AI 使用的基地建造、管理、仓储和 MCP 工具。

本仓库公开开发源码、原生桥接、构建与资产生成工具、安装器、实验候选和验证代码。项目仍在开发，**当前版本尚未达到完整可玩验收**。

## 当前状态

截至 2026-10-07，开发环境为 macOS、CrossOver、《幻兽帕鲁》Steam 离线单机和本地 Minecraft 后端。既有 AI 生存建造、基地管理和箱子整理代码，以及跨游戏原生桥接、安装器和 MCP 工具均已公开。

上一轮隔离运行已完成真实世界快照、完整目标模型与碰撞提交和本次世界 ACK，MC HUD 像素也已实际导出、编码和解码。这些记录只证明各自的数据链路；前台 HUD、物理输入、变身和完整生存玩法仍待验收。

最新单机候选已正常保存、停止旧运行、更新并应用配置迁移；新冷启动在 Windows 快捷方式创建步骤失败。该故障的 [修正组件](workstreams/cua-native-menu-v2) 已完成实际文件创建和读回验证，正准备正常更新。游戏和 MC 当前均关闭，新的应用启动与玩法仍待验收，见 [开发状态](docs/STATUS.md)。

最新修正源码分别保存在 [玩家保存与重启流程](workstreams/normal-journal-owned-player-flow-v2)、[原生实体身份绑定](workstreams/native-entity-binding-next)、[MCP 身份观察](workstreams/MC-local-scope-observation-next) 和 [Windows 快捷方式生成备选](workstreams/windows-shelllink-stdlib-alternative)。备选只有格式与源码检查，尚未证明实际 vendor 解析成功。

MC 10.7 复活同步与 macOS 13 ARM64 HUD 已提供 [实验发布包](https://github.com/adkeb/palcraft-fusion/releases)。MC 当前产物可按 [源码构建说明](player-standalone/README.zh-CN.md) 追溯和重组；全新环境的完整源码编译仍待验证。

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
