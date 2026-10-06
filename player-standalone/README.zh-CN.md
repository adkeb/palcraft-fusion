普通玩家 Mac 离线单机安装器源码
========================

本目录提供安装器源码和组合规格。完整 portable base 与 Model4 资产须由自己的合法本地来源准备。
普通安装继续使用原 install/update/rollback/uninstall 事务。当前模组文件名与 SHA 从发布清单中
唯一的 minecraft_mod 角色取得；文件名可以保留 10.6，实际内容为清单选择的 10.7。
实机与像素验收仍待完成。
没有作者 Saved、世界、SID、私钥、权限或日志卷。当前流程不使用 SSH、5090 或 WindowsTasks。

准备自己的正版 Palworld 文件、合法 Steam-ready CrossOver bottle、CrossOver.app，
以及正常 Java25/Minecraft26.3/Fabric0.19.5 Mac 软件依赖目录。backend-root 指向这个目录，
包括 client/libraries、assets、server/fabric-server-launch.jar 和 setup/mac-dependency-plan.json。
官方软件/资产照原合法安装方案取得，不将 vanilla Minecraft/账户复制进本包。
保留自己的 MC world/playerdata/ledger；未准备它们时先按正常 Minecraft 安装流程准备。

把 resume-parameters.example.json 的 null 换成自己已经正常选择/观察的单机 world 目录、Pal UID、
Saved/SaveGames 数字目录和坐标原点。填写自己的 MC 名称；mc_uuid=null 时按该名称的原
OfflinePlayer 算法计算普通 UUID，不生成一个替代旧玩家的 UUID。已有 MC 玩家必须填写原名称/UUID。
新用户先通过正常单机菜单建立/选择自己的世界，不使用作者世界或本包造身份。
安装与实际授权分开：初始 profile 的 SID=null、enrollment_pending=true，不能授权输入。

安装到任意自己的独立目录，例如含中文和空格的目录：

```sh
python3 launcher/install_standalone.py install \
  --root '/你的目录/我的 PalCraft' --game '/自己的正版 Palworld' \
  --resume-parameters '/自己的 resume.json' \
  --bottle '自己的 Steam Bottle' --bottle-root '/自己的 Bottles/自己的 Steam Bottle' \
  --crossover-app '/自己的 CrossOver.app' --backend-root '/自己的 Mac Minecraft 软件根' \
  --dry-run
```

核对后去掉 --dry-run。可选 --game-copy-mode apfs-clone 仅用于同一 APFS 卷。
默认 existing-selected 只读选定 bottle；create-owned 只创建 PalCraft-Player-* bottle，
它仍需正常官方 VC/Steam 安装和自己的合法账户登录，空 bottle 不等于 Steam-ready。
初始安装不启动游戏/后端，也不读写原 Steam、账户或 Saved。
原工具生成的 .palcraft/standalone/scope.json 与 backend/MCP 配置均由所选 root、bottle、app、backend-root
推导，不含作者路径或实际 boot SID。模型/材质等随本包完整 base 安装，不要求复制作者安装目录。

将自己的完整私有 UserDir 通过原正常保存退出后的迁移流程搬入 PalCraft-Client-User，
或在此私有目录正常创建自己的世界。保留 Saved/LocalData/UserOption/备份；不改角色数据。
准备本包的同组 MC 模组到自己后端的三个正常模组位置（不会修改 world/playerdata）：

```sh
python3 launcher/install_standalone.py backend --root '/你的目录/我的 PalCraft' --dry-run
python3 launcher/install_standalone.py backend --root '/你的目录/我的 PalCraft'
python3 '/你的目录/我的 PalCraft/PalCraft-Dev/player-tools/launcher/palcraft.py' start \
  --root '/你的目录/我的 PalCraft' --boot-singleplayer
```

正常菜单加载自己的世界；standalone/normal-load-copied-SP-world.lua 也通过原 scope 取得自己的
world 与 Level 路径由自己的配置提供。原 queue_player_operation.py、
observe-owned-SP-integration-context.lua、publish_standalone_permission.py 完成真实当前
PID/FILETIME/code/loaded-world 观察；之后使用原 SessionEnrollment enroll/verify 与 registry，
将真正本轮凭据写到本安装 .palcraft/credentials/credential.json。不要复用前一次 SID/授权。
本包不新增登记协议或生成假 grant，观察/许可仍由原接口验证。

原正常登记得到公开 guest 清单后，准备本轮公开 profile（不会显示私钥）：

```sh
python3 launcher/install_standalone.py enrollment-profile --root '/你的目录/我的 PalCraft' \
  --guest-manifest '/本轮正常 guest.json' --output '/本轮公开 profile.json'
python3 '/你的目录/我的 PalCraft/PalCraft-Dev/player-tools/mac/scripts/prepare_launch.py' \
  --config '/你的目录/我的 PalCraft/PalCraft-Dev/player-tools/standalone/mac-runtime-config.json'
```

用原 start_role.py --launch ROLE.json --sync-receipt 正常同步回执启动 sharedMC/guest/HUD。
Java/HUD 同一 file-map、服务端实体 RPC/entities 与视觉 mirror bridge/entities 自动跟随新 root。
原 sync receipt 仍需正常 save/stop、相同 UUID 与 world/ledger 和当前实际登记事实。
原 747 promote --root ROOT --profile 本轮公开profile 附加 proxy/HUD，保同一 Host/Game 与 realm。
23 个 MCP 工具入口为 ROOT/PalCraft-Dev/mcp/server.py；AI/MC 各自配置由安装生成，原协议保持。

正常退出、维护与日志分卷
----------------------

Pal 正常 AutoSave/返回标题/Quit，MC 正常 save/stop，原 public stop 收尾本次 proxy/HUD。
如果本机独立安装要开启新的正常事件卷，必须先取得这一 root 的原正常 stop 维护回执。
使用原 producer/consumer 全停事实，不以日期或 GUI 消失代替。仅这个 event stream 分卷：

```sh
python3 launcher/install_standalone.py rotate-events --root '/你的目录/我的 PalCraft' \
  --normal-stop-receipt '/本 root 的正常维护回执.json' --dry-run
python3 launcher/install_standalone.py rotate-events --root '/你的目录/我的 PalCraft' \
  --normal-stop-receipt '/本 root 的正常维护回执.json'
```

旧 palcraft-events.ndjson 原字节移到 RPC/journal-archives/，保存 SHA/大小回执；active 原 path
由原 writer 下次正常 full snapshot 启动重新创建。没有 reader offset、copyrow、假 ACK 或 skip。
运行中的单机、MP 和其他玩家不能使用该入口；Saved、MCworld、food/escrow WAL、travel ACK 不动。
新进程重新正常 Load/观察/enroll/PV/R64，避免新 reader 从旧 1GB 生命周期历史卷重放。

监督器异常时使用原 status/recover-session 请求本 token 的正常退出，不按旧 PID 操作其他程序。
正常卸载使用下面命令：原 installer 默认保留整个私有 Saved；仅删除本包登记且未修改的后端模组，
自己的 backend world/playerdata/ledger 与修改过的文件保留，所选 bottle 保留。

```sh
python3 launcher/install_standalone.py uninstall --root '/你的目录/我的 PalCraft' --dry-run
python3 launcher/install_standalone.py uninstall --root '/你的目录/我的 PalCraft'
```

组合公开源码与 macOS 13 HUD
-------------------------

build/public-standalone/compose-spec.json 明确列出同一冻结实现的 core/standalone 和两个真实模块：
multiplayer/session_client.py 为 session_client，sign-text/python/receiver.py 为 sign_text_receiver。
两模块仅依赖 Python 标准库；strict-player 和 sign_text_transport_enabled 保持启用。
准备原完整 base，并将已发布的 hud-overlay-v5-public-macos13 放到 mac/ 目录后，使用：

```sh
python3 -m installer.compose_standalone \
  --base-release '/自己的完整 release.zip' --overlay-root . \
  --spec build/public-standalone/compose-spec.json --output '/新的输出/public-hud13.zip'
```

规格绑定公开 Swift 0a74168b 与 macOS 13 arm64 二进制 0cc13814；组合器检查模组和所需代理角色唯一，
随后由原安装入口执行 Bundle 全量验证。角色检查本身不代表完成安装或授权。
私有冻结批次已通过原 Bundle 完整加载、当前模组配置、三个受管理后端模组更新和代理模块加载。
公开源码沿用相同 core/standalone/模块字节；公开 HUD 的 macOS 13 实机运行及像素验证仍待完成。

复现历史 10.6 JAR（D04）
------------------

```sh
python3 launcher/build_mc_10_6.py \
  --base-mod '/自己的 exact10.5-c35dbd.jar' --jdk-home '/自己的 JDK25/Contents/Home' \
  --runtime-root '/自己的 Mac Minecraft 软件根' --output '/新的输出/10.6.jar'
```

build/mc10_6 包含两份冻结 Java、相对 classpath 依赖与实际 zip 元数据 recipe。
真实本地 javac 只编译 HostState/HostLink，更新三项 class 与 version，保原 169 entry/168 class。
已用本入口一次实际重现完整 401a4ae60eb428d106aba448d42ba3a74b28eb7d06624184bc247228b58a89af；
没有游戏/网络/GUI，原 19 检查没有重跑。JDK25.0.4.1、exact10.5 base 与记录依赖为复现前提。
Build receipt 不是 HUD 像素或可玩性验收。


2026-10-07 构建验证更新：公开 `build_mc_10_7.py` 和配方未修改，从六个生产源在全新的编译输出目录实际产生 11 个 class；未传入旧 compiled-production。三个 JVM 步骤均成功，最终 552361 字节 JAR 的 SHA-256 与当前 F35 完全一致。使用了本机现有合法依赖缓存，未下载或启动游戏。此结果验证增量构建，完整 118 源 Gradle 项目和其他用户全新环境仍未证明。详见 [安全构建记录](../docs/evidence/MC10.7-fresh-six-source-compile.json)。
