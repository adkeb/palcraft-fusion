# 一份真实 Wood：Pal → MC → Pal，运行会话执行稿

仅 source/prep。本分支未调用 RPC、GUI、游戏、服务或存档操作。当前 918 client-only form switch 继续由 runtime 独占；以下步骤留给其后既有自动启动/标准 Fabric 功能窗口。只复用现有 escrow_setup / exchange v3 store / ResourceExchange / registrar / watcher，不增加兑换协调器。

## 已同步的实物事实

* `palcraft/runtime/evidence/10_1-actual-boot-certificate.json`：boot `00000000-0000-4000-8000-000000000034`，Pal PID40280，实际 full-world finalized，world `AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA`。同 PID 正常重连证据也已存在。无需为“补 boot 修复”再重启。
* 10.1 Pal public runtime-config 已 `exchange_enabled=true`、`boot_observer_enabled=true`，trusted root 是 `D:/PalworldServer-LAN/PalCraft-Dev/bridge/exchange`。
* **实际** `10_1-initial-complete-world.json` 与 `10_1-sameprocess-rejoin-complete.json` 的 MC hello feature flag 均 `exchange_enabled=false`。profile 中写 true 不能替代这个实际状态。
* 上述实物的身份为 MC `11111111-1111-1111-1111-111111111111` ↔ Pal `22222222-0000-0000-0000-000000000000`。下一窗口须从正常重连的严格身份路径确认仍是这对实际角色；不以历史 UID 或第一个 controller 代替。
* 10_1 增量包包含 v3 Lua/store、两 native DLL、Python watcher/credit/witness 与带 reserved-ID lookup 的 `discovery.lua`。其中没有 `escrow_setup.lua`、`escrow_enroll.py`、survey/operator helper；增量缺文件不等于安装目录必然缺文件，runtime 先按实际部署清单核对。
* 最新同步材料没有当前 paid-box census / `escrow-config.json` / setup WAL 实物。历史 paid serial 箱在基地内且非空，不能据此声称已找到本次空隔离箱。

## 一次性配置与正常重载边界

| 项目 | 实际入口 / 配置 | 正常重载要求 |
| --- | --- | --- |
| MC feature | `-Dpalcraft.exchange.enabled=true` | 要进入实际 dedicated server JVM；与下一 standard Fabric 正常服务启动合并。remote guest 走该 server 的 feature gate。 |
| MC shared root | `-Dpalcraft.exchangeDir=D:/PalworldServer-LAN/PalCraft-Dev/bridge/exchange` | 与上项一起进入实际 server JVM。若已有同值不用重复修改。 |
| 标准启动生成 | 现有 `Prepare-Standard-Launch.ps1` 读取 public config 的 `server_jvm_args` 并写 `launch/server.args` | 把上两项合并入该数组，保留已有其他 public args；由既有标准迁移/启动 owner 重新生成并正常启动。当前 server.json `configured_for_runtime_batch=false` 是准备模板，不能直接当已配置启动事实。 |
| Pal env/feature | 既有 startup `PALCRAFT_EXCHANGE_ROOT` 与 Pal `exchange_enabled=true` | 10.1 已配置。仅补 helper 文件和真实登记 config 不要求单独 Pal restart；`server_options.exchange_ready()` 动态读该 config。 |
| Pal 付费登记 | `escrow-config.json`，仅已有 `escrow_enroll.py` 生成 | 实际正常成本/完整空箱/WAL/已安装 Level 匹配后一次创建。无 config 不会默认造箱或放行。 |
| 角色映射 | root 下 `players.json`：实际 MC UUID → 实际 Pal UID | 若已存在且匹配，原样复用；若缺失，用实际严格身份确认的映射通过现有 `exchange_recovery.atomic_write` 合并一次。保留其他映射；冲突先查实际绑定，不自动覆盖。MC 每次 request 都读取，无需因此重启。 |
| 保存见证 | 一个现有 `exchange_recovery.py witness --watch` | 是外部正常保存执行者，无需 Pal reload。只保留一个同 root worker，不并行重复启动。 |

若标准 MC 世界迁移与兑换合并，先用现有 Status 确认旧世界没有未完成交易，再完成标准迁移/正常启动，重连实际角色，确认 hello flag=true、world view ready，之后才开始这笔试验。MC intent 自行绑定 `server.getWorldPath(ROOT)`，不手写旧世界路径。Pal 若因其他既有部署必须正常 restart，沿用 prepare → normal start → complete，使用新实际证据，不硬编码 ff0/PID40280。

## 先检查箱，再做正常成本与工作

在现有 BridgeLab `Scripts/` 下准备这些现有/薄 wrapper 文件：

* `palcraft/server/escrow_setup.lua`，精确 SHA `cc6b7d819a762f3aae30dfc3801c273a99bbc3637629078f7eb445b827837867`。
* `escrow-storage/escrow_lab_probe.lua` 与本次 `escrow-storage/escrow_operator.lua`。
* Python MCP 目录补 `palcraft/mcp/escrow_enroll.py`，继续用实际已有 pinned Python/vendor/pyooz，不能改用缺 ooz 的本机 Python3.9。

wrapper 只转发显式现有调用，加载不调度、不建箱，默认 survey。下面片段由 runtime 在同一个实际 game-thread dispatcher 调用并保存真实返回 JSON：

```lua
local dir='D:/PalworldServer-LAN/BridgeLab/Pal/Binaries/Win64/ue4ss/Mods/PalLiveBridge/Scripts/'
local op=dofile(dir..'escrow_operator.lua')
return op.run('survey')
```

核对当前实际 owner/guild、所有基地范围、完整普通箱绑定和全部槽位。已登记且仍合格的空隔离箱直接复用；若有已完成且已落盘的 paid setup WAL，可用它的真实 setupId 登记现箱。仅 survey 找到未登记空箱不等于现有 registrar 已验证其生存成本：它只接受真实 normal_paid_escrow_setup revision/durable copies，不能编造 paid=true 或给普通旧箱套一个虚假 setupId。

无可复用且成本已证明的现箱时，才走已有正常建箱：

```lua
return op.run('preview',{pal_uid=actualPalUid})
-- 只在返回真实 shortage 时取当前 guild 的真实库存，随后重新 preview：
return op.run('take_stock',{pal_uid=actualPalUid})
-- 采用本实例真实 preview.id，在60秒内 submit；仅一次 consuming build：
return op.run('submit',{setup_id=actualSetupId})
return op.run('start_work',{setup_id=actualSetupId})
-- 约2秒一次普通 observe，直到 ready_for_saved_enrollment：
return op.run('observe',{setup_id=actualSetupId})
```

以上为分次调用示意。`op` 每次可重新 dofile，内部沿用同一 `_G.PalCraftEscrowSetup`，不丢 60 秒 preview plan。真实 recipe/tech/guild permission、地面/净空/all-base +10m 仍由 cc6b helper 检查。正常扣 15 Wood +5 Stone；普通 worker/实际工作进度完成，不能 grant、直接写 HP、写 progress、instantconstruct。短缺、tech 未解锁、trace/RPC/work 具体错误保留真实原因。submit 或 native 成本响应不明时继续 observe 原 setupId，不能再建一箱来“重试”。

## 登记与外部 worker

只有 helper 真正 `ready_for_saved_enrollment` 后，runtime 用既有唯一保存执行者发普通 Lab save，并等待实际 Level 含这份完成/空箱数据。现有 registrar 检查实际 cost delta、所有 durable setup revisions、同一已安装 Level 的 model/concrete/module/container、ownership、capacity/position 和空槽，随后写 config；它不会写游戏存档或假交易见证。

本次 `Invoke-Escrow-Existing.ps1` 只是包装原 CLI；默认 Status。`$PythonInterpreter` 和 `$PatchedParserVendor` 必须是 runtime 已用成功的实际 Windows 路径，`$ActualSetupId` 是真实 helper 返回值：

```powershell
./Invoke-Escrow-Existing.ps1 -PythonInterpreter $PythonInterpreter -Mode Status
./Invoke-Escrow-Existing.ps1 -PythonInterpreter $PythonInterpreter -Mode Enroll `
  -SetupId $ActualSetupId -ParserVendor $PatchedParserVendor -LabCandidate
./Invoke-Escrow-Existing.ps1 -PythonInterpreter $PythonInterpreter -Mode Watch `
  -ParserVendor $PatchedParserVendor
```

非 Status 默认从已有实际 boot certificate 读取 installed Level 路径，现有 CLI 继续做真实校验。Enroll 是显式单次动作，已有 config 不替换；Watch 复用既有 REST/save 回调、完整 Level/保存收据验证、MC NBT proof 和 credit permit，约1秒 tick；不创建 MC intent，不手写 request/result/receipt。若已运行同 root watcher，只复用它。

`-LabCandidate` 仅是已授权测试 Lab 的未知 native-credit/daily-isolation 状态标记，`credit_verified=false`、`runtime_isolation_verified=false` 保留。它不能当作普通玩家 strict 完全通过。

## 一份材料的现有正常入口与终点

MC 现有入口是 `ExchangeScreen → ClientBridge.exchange → authenticated BridgeNetwork → ResourceExchange.request`。UI 默认 **8份**，数量按钮循环 `8→32→1`，先点击两次切到 1。现有 HostLink `dispatch` **没有 exchange/exchange_balance case**；不能把裸 `{"t":"exchange",...}` 发给 WebSocket 当已执行。走现有背包的材料兑换入口：InventoryScreen 底部中央区域由原 ClientInput 接收 RMB 打开 ExchangeScreen，再用真实界面按钮。

1. 查看余额并保存初始真实 Pal bag/source counts、MC oak_log count。实际 Pal 角色在线、普通生存、至少有 Wood1；MC 有接收空间，view 不在 waiting_ack。建箱若恰好用光15 Wood，另用普通采集/已有库存取得这1份，不能补送。v3 的基地来源只有角色实际处于同 guild 基地范围内才可用，单有 enrollment.source_base_id 不会跨位置自动供料；角色不在基地时应有真实 bag Wood1。将 UI 数量切到1。
2. Wood 行点“转入 MC”：正常 Pal moveIn1 → actual full Level/source witness → 正常 MC credit oak_log1+saved receipt → 正常 Pal dispose1 → actual empty Level → v3 release。记录真正生成的 txId，不自己生成 MC WAL。
3. 等现有 Status 无未完成交易，且 `mc-<id>.json` 是 `completed`、`escrow_empty_durable=true`、**`pal_released=true`**；current lease `released`。只有 MC completed 或 UI 超时均不算结束，不能开始另一笔替代。
4. 同一 Wood 行点“转回帕鲁”，数量仍1：正常 MC debit 上步所得 oak_log1+saved marker → 原 worker 生成 NBT-backed 一次性 permit → Pal native produce Wood1 到托管箱 → actual full Level → 正常 Move 到真实 Pal bag → actual empty Level/bag witness → completed+pal_released。
5. 再确认无 pending、lease released、托管箱全空。两笔 roundtrip 的合计应是 MC oak_log 净0、Pal Wood 总量净0，返还的 Wood1 在真实包；建箱的 Wood15/Stone5 是另外的已发生正常成本，按兑换前基线单独记录。保存两 tx 的真实 WAL/full/empty/MC saved receipt/最终数量。

第一方向成功只证明正常移入/MC入账/清理；第二方向才触发尚未实机验收的 native produce。产出响应不确定、beforeimage/afterimage不一致或 permit claim 后失败时保留原 transaction，按现有恢复入口读回，不追加一次 credit，也不补送材料。此窗口是一笔功能闭环，不重复 old recovery matrix。

## 接受范围与本轮检查

带 registry lookup 的 discovery 已在10.1包中，但实际外部 AI organizer/native 快速整理是否都调用该排除仍未证明；箱在所有基地 +10m 之外也不能替代这一项。普通 RPC 参数过滤/交互拒绝、玩家开箱/运输/供料日常路径及 native produce 仍须实机观察。一次成功 roundtrip 不自动给 `isolation_evidence.runtime_verified` 或 credit_verified 赋 true；无额外 certificate 层。

本轮只跑新 Lua wrapper 的 `luac -p`，nice19，通过。没有本地 PowerShell，PS1 仅源码审阅，未宣称 Windows 执行通过；没有调用封装的 Enroll/Watch 或旧 matrix。现有 cc6b helper、v3 Lua/Java/Python、运行 config 与实际存档均未修改。

## 新实物供料已就绪：base-food-single-base-storage

已核同步回执 SHA c2a9ef6bd1c009dcc474d2cbee43251664fe47d7ebf1feb24ac498d4f8bddea2（单一额外库存读取、0 mutation），实际 session steam_null_0000000000。成本来源是普通 CID `00000000-0000-4000-8000-000000000013`，model `00000000-0000-4000-8000-00000000001a`，base `00000000-0000-4000-8000-000000000031`，guild `00000000-0000-4000-8000-00000000001b`；slot6 Stone218、slot8 Wood8028，dynamic GUID 全零、live ownership/eligible true。该箱10槽占用，是供料源，不能当空 escrow。

当前最短正常步骤是同一 cc6b helper `take_stock(actualUID)` → `preview(actualUID)` → 真实 preview.id 的单次 submit → normal start_work1000 → observe原id → 保存/原registrar登记。当前管理链选择实际 UID `22222222-0000-0000-0000-000000000000`；仍需 runtime 采用其当前真实presence。take_stock只取 max(0,15-carriedWood)、max(0,5-carriedStone)，不固定额外拿15/5；其已存操作会记真实sourceCID/slot/n。现有函数只有UID参数，按当前guild最近base遍历源，没有CID/slot pin API，不能声称已锁死只取上述箱。必要的本次移动live recheck仍由现有方法内部做，不追加独立storage诊断或宽矩阵。

已有 helper 要求同UID实际connected PalPlayerController/NetConnection及正常player-owned Transmitter。没有PC时会真实拒绝，这是连接RPC组件限制而非材料不足；不拿offline account冒充、不改成free/instantSpawn。完整客户端图形修复和全产品release不是部署/准备serverpaidsetup的前置；实际正常组件可用时runtime即可执行。HP/科技不由本operator改变。
