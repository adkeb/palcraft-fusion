# PalCraft Fusion

《幻兽帕鲁》× Minecraft 联动，以及供 AI 使用的基地建造、管理、仓储和 MCP 工具。

公开作者源码、原生桥接、构建与资产生成工具、安装器和实验组件。**项目仍在开发，尚未完成完整可玩验收。**

## 当前状态

2026-10-08，实机开发环境为 macOS、CrossOver、Steam 离线单机与本地 Minecraft 后端。候选 32 已通过普通更新、原世界冷加载和首次自动世界同步，保留上一版正常合成与保存的物品。实机画面已出现 MC 炉子和工作台。

前一轮已实际完成 F5 切换、背包合成、正常保存与返回标题、客户端正常退出，以及本次运行内的四组件帧率调整。候选 33 已完成普通更新、首次自动世界同步与实机光标回中；持续转向仍被回中位移抵消，正在修输入处理。箱子、烧炼、兑换和其余玩法继续推进。上述结果是限定流程证据，完整 42 项要求尚未通过。

查看 [当前状态和验收范围](docs/STATUS.md)、[构建说明](docs/BUILD.md) 和 [Standalone 安装源码说明](player-standalone/README.zh-CN.md)。[实验发布包](https://github.com/adkeb/palcraft-fusion/releases) 提供部分已公开组件；完整玩家版仍待完成。

当前 MC 10.10 已通过 [全部生产源重建](workstreams/current-mc10-10-source-build)，输出与现用包精确匹配；原生输入组件也提供 [四个编译单元的完整源码构建](workstreams/current-native33-source-build)。两项均无需旧项目编译产物，具体工具链和验证边界见构建说明。

## 源码地图

| 目录 | 内容 |
| --- | --- |
| `palcraft/client`、`palcraft/server` | Lua 客户端与权威侧组合、模型、碰撞、物品、实体、流体、维度与角色控制 |
| `palcraft/mc` | Minecraft/Fabric Java 联动基础；后续增量见 `workstreams` |
| `palcraft/native`、`palcraft/render` | Unreal 网格、碰撞、输入、相机、材质、共享帧和原生桥接 |
| `palcraft/mcp` | AI 基地与仓储工具、MC 控制工具及本地队列适配器 |
| `palcraft/installer`、`palcraft/launcher`、`player-standalone` | 安装、启动、会话、恢复、构建与卸载实现 |
| `mac` | macOS HUD、帧传输和本地后端脚本 |
| `palworld-live`、`palworld` | AI 生存建造、基地管理、材料消费、箱子合并分类 |
| `modules`、`workstreams`、`experimental` | 各项源码增量、构建配方与限定验证范围 |
| `palcraft/tests` 及模块内 `tests` | 现有针对性测试与验证工具 |
| `tools/legacy` | 历史作者工具；当前启动入口见安装说明 |

最新控制与生命周期增量见 [Mac 光标捕获](workstreams/mac-owned-host-cursor-capture)、[权威快照晚接入补齐](workstreams/late-authoritative-snapshot-native-catchup)、[正常已保存世界关闭](workstreams/normal-saved-world-shutdown) 和 [在线性能设置](workstreams/live-owned-power-profile)。每项保留适用基线和验证范围。 连续回中新增 [RAW 输入与物理捕获分离](workstreams/native-raw-host-capture)，原生组件编译与限定源码案例通过，实机结果仍待候选 33。

## 使用与资源

需要自行提供合法安装的游戏、CrossOver、Java 和 Fabric 依赖。模型与纹理由本仓库的提取、转换和生成工具在自己的本机生成。

公共配置使用占位参数；世界、玩家和授权由自己的正常加载、观察与登记流程取得。基地建造遵守正常生存的科技与材料成本，仓储沿原物品系统执行。

个人存档、账号凭据、私钥、运行队列、交易日志和个人测试快照未公开。商用游戏文件及提取的纹理、模型不随仓库发布。

## 许可

作者扩展沿用 [MIT](LICENSE)，第三方代码与接口保留原许可和 [说明](THIRD_PARTY.md)。Minecraft、Palworld、CrossOver 与 Unreal 的商用文件不在本仓库许可授予范围内。

历史候选与排查结果见 [开发记录](docs/history/2026-10-07-development-record.md)。
