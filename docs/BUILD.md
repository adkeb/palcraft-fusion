# 构建与资源生成

## Minecraft 模块

Java 源码位于 `palcraft/mc`。使用 JDK 25 和对应的 Gradle/Fabric 依赖构建；游戏版本与依赖版本由项目的 Gradle 文件声明。

当前源码版本为 `0.2.0-integration.10.7-respawn`，包含基于 10.6 的六文件复活同步候选。Java 编译通过不代表运行中的 Mixin 注入或正常复活流程已经验证。

```sh
cd palcraft/mc
gradle build
```

原始 10.6 快照的 Gradle 属性仍沿用 10.5 标签，10.6 的实际成品通过两份 Java 增量和保持原 JAR 结构的装包流程生成。普通 Gradle 构建不等同于字节一致的历史成品。历史 10.6 的字节一致专用重建入口为 `player-standalone/launcher/build_mc_10_6.py`，构建配方位于 `player-standalone/build/mc10_6`。该入口已实际重现原 10.6 成品的 SHA256；它不是当前 10.7 候选的构建入口。

当前 10.7 的专用入口为 `player-standalone/launcher/build_mc_10_7.py`，相对配方和说明见 [10.7 构建指南](../player-standalone/build/mc10_7/BUILD.zh-CN.md)。公开快照为 118 个成员（原私有 119 成员中的 wrapper JAR 被排除），六个实际生产源与 11 个 class pin 保持。该公开入口已真正重新编译六份源、生成 11 个新 class，重现 F35／552361B；见 [六源编译回执](evidence/MC10.7-fresh-six-source-compile.json)。

构建基础包可使用 [完整 100 生产源入口](../player-standalone/full-mc-source/BUILD.zh-CN.md)。此入口已在本机从新编译的 168 个 class 重现 exact10.6，再衔接六源输出得到相同 10.7 产物，旧项目 class 字节复用为 0。用户仍需自行提供配方中的合法依赖；其他用户全新环境和完整项目 Gradle 构建尚未验证。

Gradle wrapper 的依赖 JAR、Minecraft/Fabric 库和游戏客户端不作为本仓库源码附件提供，使用官方依赖流程取得。

## 原生桥接

`palcraft/native`、`palcraft/render` 和 `palcraft/ue4ss-utf8-shim` 包含作者源码；原生模块按对应构建脚本使用 Windows 工具链或 Mac 上的跨编译工具链。匹配目标游戏版本与 ABI 后再安装，不能将某次地址/签名验证扩展为所有版本兼容。

Lua 代码位于 `palcraft/client`、`palcraft/server`，后者在 Standalone 中可以通过既有客户端 Lua VM 加载权威功能。需要合法安装的 UE4SS 运行基础，许可见 `third-party/notices`。

## macOS HUD

HUD 源码位于 `mac/hud`。使用 Swift/AppKit 与系统图形框架构建，帧中继使用 Python。真实 MC 帧通过原共享文件和 PHUD/HCLK 协议传输；离线 Steam 设置不关闭本地环回网络。

公开 HUD 使用 `PALCRAFT_BRIDGE_DIR` 指定桥接目录；未设置时使用当前用户的 `~/Library/Application Support/PalCraft/bridge`。arm64 候选以 macOS 13 为最低部署目标编译，已回读 Mach-O `minos 13.0`；这不代替 macOS 13 上的实际运行验收。

```sh
cd mac/hud
nice -n 19 swiftc -O -target arm64-apple-macosx13.0 hud_overlay.swift -lz -o hud-overlay-v5-public-macos13
```

该次基础 HUD 构建的源码、二进制哈希与工具链记录见 [HUD 构建回执](evidence/HUD-v5-BUILD-macos13.json)。当前候选使用追加前台进程归属组的 [HUD 源码与构建入口](../workstreams/mac-owned-foreground-group/README.md)，并搭配 [启动阶段修复](../workstreams/mac-hud-normal-starting-phase/README.md)。请按对应增量的基线与哈希组合，基础 HUD v5 发布包不能代替这些新构件。实际前台 HUD 显示仍在验收。

## 资产生成

模型、纹理、实体姿态和材质工具位于 `tools`、`modules`、`workstreams`。从自己的合法游戏资源生成本地资源，保留原版 UV、alpha、动画与模型语义。仓库中的生成器源码可以发布，生成的商用游戏资产不能视作本仓库原创资产。

## 配置和安装

请配置自己的根目录、CrossOver bottle、游戏复制来源、后端目录、世界和玩家；不要复用别人的身份或会话。个人目标容器与基地列表由本地发现生成，`targets.lua` 为公共空模板。

原安装器、启动器和 MCP 源码已公开。便携安装候选仍在整合，使用前确认当前状态和与源码对应的构件版本，不把本仓库当作完成全部实机验收的发行包。

完整普通入口必须包含真实依赖角色：`strict-player` 发布包需要 `session_client`，启用告示牌传输时需要 `sign_text_receiver`。对应标准库模块位于 `player-standalone/multiplayer/session_client.py` 和 `player-standalone/sign-text/python/receiver.py`，由原代理动态加载，不能以空角色或关闭功能代替。

Standalone 配置从当前唯一 `minecraft_mod` 角色读取文件名与 SHA。已有三个后端副本仅在本安装记录的旧哈希与当前文件一致时更新；未管理或被改动的文件保持拒绝。一次临时目录验证已覆盖原 `Bundle` 加载、配置生成、已有后端更新和代理模块加载，见 [原入口检查](evidence/ordinary-entry-dependency-check.json)。它不代表实际认证或游戏内流程通过。

## 普通玩家 Standalone 入口

`player-standalone/launcher/install_standalone.py` 和 `player-standalone/installer/compose_standalone.py` 复用原安装器，接受自己的游戏、根目录、bottle、CrossOver 和后端参数。详见 `player-standalone/README.zh-CN.md`；公共源码树不包含它需要的游戏本体或本机生成资产。

公开源码组合规格为 `player-standalone/build/public-standalone/compose-spec.json`，绑定已发布的 macOS 13 arm64 HUD。组合器要求唯一的模组、实际会话和告示牌依赖角色；本次源码子集组合与模块加载检查见 [公开入口检查](evidence/public-standalone-source-closure-check.json)。完整基础包和游戏资产由用户在本机准备。
