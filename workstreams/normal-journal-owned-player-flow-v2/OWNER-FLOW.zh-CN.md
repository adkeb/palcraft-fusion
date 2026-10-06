v2 profile 迁移、普通日志生命周期和原生 menu 源码闭包
==================================================

这份源码以 runtime a783 为 base，保留 --enable-alt-loader 1，并合入 journal v1 的完整功能增量。Menu 只合 input owner 冻结的三行包装和原 d0389def 组件源；原 client argv、session/supervisor/root/UserDir/Win32 job host 路径仍保留。官方 vendor Menu Helper 二进制与资源由玩家本机合法 CrossOver 提供，本源包不包含这些文件，也没有实机 app 注册或 F5 成功结论。

当前实验实例的 profile 缺 standalone。私有迁移计划只是只读生成，不能将“四个源码文件装入”称作已接通。在正常 allOff 前，本计划不应用，也不按 PID 接管外部 sharedMC/guest。原 server/world 整目录、现版本 world/players/data 的同 UUID 背包、guest options/cache/libraries、world origin、ledger/WAL 均保留，不复制、不初始化、不改 NBT。

sole runtime 执行顺序：

1. 正常 save/Level witness、Title/Quit、native exit0、guest exit、server console stop0、所有这一 stream actor allOff，留下本轮原真实停机回执。
2. 用原 update 应用 root 审核的 candidate7。此时尚保留旧 profile，不在 update 和 profile 迁移之间启动游戏。paid 两个 client slots 与 menu/本增量可同一可靠组合规格组包。
3. 在已安装的新工具中，重新生成本轮私有迁移计划。旧预览含 profile/manifest SHA，candidate 更新后必须重新生成。参数来自玩家自己的现有配置：

```sh
python3 -m installer.standalone_transition plan \
  --root '/自己的 PalCraft' --backend-root '/自己的现有 Mac Minecraft 后端' \
  --existing-config '/原本已使用的 mac-runtime-config.json' \
  --existing-launch-dir '/原本已使用的 launch' --output '/新的私有 transition-plan.json'
python3 -m installer.standalone_transition apply \
  --plan '/本轮私有 transition-plan.json' --normal-stop-receipt '/本轮原完整 allOff.json' --dry-run
python3 -m installer.standalone_transition apply \
  --plan '/本轮私有 transition-plan.json' --normal-stop-receipt '/本轮原完整 allOff.json'
```

apply 使用原 core 的 backup/journal/undo/state 原子事务，限制为配置目的路径；manifest/current/所有原 payload 的 managed SHA 保持。只读写这些小配置，不重 hash/copy 8k 模型资产。profile 新增标准 standalone 参数，保持原 identity/world origin/bottle/app/性能等字段，cold SID=null、enrollment_pending=true。保留原后端未知选项和全部角色 argv；后续 generated_files 也保留这些显式后端参数，仍从当前唯一 minecraft_mod 取得目标文件名和 SHA。

4. 使用原 cold bootstrap；尚有旧卷时显式提供上面的本卷完整停机回执。原 rotate_events 已归档且 active 不存在时，无需重复归档。通过正常 UI Load 原世界，原 process/loaded-save 观察、权限、issuer enroll/verify 和本轮公开 profile 不变。
5. 原 enrollment-profile 准备本轮 profile 后，对本 root 的 standalone/mac-runtime-config.json 调用原 prepare_launch。新的 prepare_launch 能读取原 argv 模板，不修改 JVM feature/night 参数、world/UUID/ledger 位置。模板元数据指向本安装的新 cfg，但角色参数仍是原合法既有数据位置。
6. 同步历史只能与本轮真正 issuer 的 fresh-sync/验签文件合并，不能把旧 actual_enrolled/SID 当成新登记。可用：

```sh
python3 -m installer.standalone_transition sync --root '/自己的 PalCraft' \
  --previous-sync '/原同 UUID world/ledger 同步历史.json' \
  --fresh-sync '/本轮原 issuer fresh-sync.json' --enrolled-profile '/本轮公开 profile.json' \
  --output '/新的本轮 sync-receipt.json'
python3 launcher/palcraft.py promote --root '/自己的 PalCraft' \
  --profile '/本轮公开 profile.json' --sync-receipt '/本轮 sync-receipt.json'
```

这一次 promote 由原同一监督器创建新的真实 Popen，并持有 server stdin/guest/relay 所有权；不是 adopt 旧 PID。RuntimeError guard 在调用边界转成具名 STANDALONE_ROLE_GUARD，原 promote_full unwind 后回 bootstrap。

7. 下一次普通 stop 使用原 save ID/r1+r2 durable intent、实际 post-submit stable Level、同 native epoch 的真实 Title/exit0、每个实际 Popen.wait 和 off 后稳定 Saved/WAL，产生本 boot/本卷完整见证；下一 cold start 自动复用原 rotator，原 writer 建立新卷。

检查复用原临时 bootstrap fixture。配置事务故障撤销、无 payload 重新 hash、MC26.3 players/data、完整 argv/night/unknown 参数保持、a783+单 menu 包装、原 promote_full guard 拒绝回 bootstrap、实际临时 server stdin stop0/guest SIGINT130/worker 内层 wait 和整卷归档均已验证。原 native-menu 十项检查不重复；native Windows save/Title/FILETIME 在我们的 fixture 中模拟，未启动实际游戏/MC/Wine/cxmenu/GUI/RPC，实际 app owner/F5/这份完整普通 lifecycle 仍须 sole runtime 验收。

GUI-only Quit、supervisor 崩溃、force/nonzero exit 或外部 reader 没有被本 boot 创建时，不自动签发完整见证。原历史同步标记不能当作新 WorldState 初始化证明。本包不带当前私有规格、作者 identity、绝对路径默认值、vendor binary、Saved、WAL、credentials 或任何 boot SID。
