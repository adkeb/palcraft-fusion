# 构建与资源生成

## Minecraft 模块

Java 源码位于 `palcraft/mc`。使用 JDK 25 和对应的 Gradle/Fabric 依赖构建；游戏版本与依赖版本由项目的 Gradle 文件声明。

当前源码版本为 `0.2.0-integration.10.7-respawn`，包含基于 10.6 的六文件复活同步候选。Java 编译通过不代表运行中的 Mixin 注入或正常复活流程已经验证。

```sh
cd palcraft/mc
gradle build
```

原始 10.6 快照的 Gradle 属性仍沿用 10.5 标签，10.6 的实际成品通过两份 Java 增量和保持原 JAR 结构的装包流程生成。普通 Gradle 构建不等同于字节一致的历史成品。历史 10.6 的字节一致专用重建入口为 `player-standalone/launcher/build_mc_10_6.py`，构建配方位于 `player-standalone/build/mc10_6`。该入口已实际重现原 10.6 成品的 SHA256；它不是当前 10.7 候选的构建入口。

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

该次构建的源码、二进制哈希与工具链记录见 [HUD 构建回执](evidence/HUD-v5-BUILD-macos13.json)。实际前台 HUD 显示仍在验收。

## 资产生成

模型、纹理、实体姿态和材质工具位于 `tools`、`modules`、`workstreams`。从自己的合法游戏资源生成本地资源，保留原版 UV、alpha、动画与模型语义。仓库中的生成器源码可以发布，生成的商用游戏资产不能视作本仓库原创资产。

## 配置和安装

请配置自己的根目录、CrossOver bottle、游戏复制来源、后端目录、世界和玩家；不要复用别人的身份或会话。个人目标容器与基地列表由本地发现生成，`targets.lua` 为公共空模板。

原安装器、启动器和 MCP 源码已公开。便携安装候选仍在整合，使用前确认当前状态和与源码对应的构件版本，不把本仓库当作完成全部实机验收的发行包。

完整普通入口必须包含真实依赖角色：`strict-player` 发布包需要 `session_client`，启用告示牌传输时需要 `sign_text_receiver`。对应标准库模块位于 `player-standalone/multiplayer/session_client.py` 和 `player-standalone/sign-text/python/receiver.py`，由原代理动态加载，不能以空角色或关闭功能代替。

Standalone 配置从当前唯一 `minecraft_mod` 角色读取文件名与 SHA。已有三个后端副本仅在本安装记录的旧哈希与当前文件一致时更新；未管理或被改动的文件保持拒绝。一次临时目录验证已覆盖原 `Bundle` 加载、配置生成、已有后端更新和代理模块加载，见 [原入口检查](evidence/ordinary-entry-dependency-check.json)。它不代表实际认证或游戏内流程通过。

## 普通玩家 Standalone 入口

`player-standalone/launcher/install_standalone.py` 和 `player-standalone/installer/compose_standalone.py` 复用原安装器，接受自己的游戏、根目录、bottle、CrossOver 和后端参数。详见 `player-standalone/README.zh-CN.md`；公共源码树不包含它需要的游戏本体或本机生成资产。
