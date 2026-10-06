# Mac 单机：付费箱 authority 后继候选与必要边界

当前人类授权是 Pal 单机测试、全部测试流程在 Mac。Steam offline 偏好不是游戏单机 authority 证据。M01 的后续多人能力/原网络源码保留，当前不启用 M01、不启动专服、不访问或复制512/生产 Saved。

本候选只解决付费箱 helper 的实际 local-PC authority 分支。网络基线 `palcraft/server/escrow_setup.lua` SHA `cc6b7d819a762f3aae30dfc3801c273a99bbc3637629078f7eb445b827837867` 原样保留；后继与独立 authority reader 成对部署。它还不是 Mac 单机兑换、保存恢复或 native credit 的实机验收。

## 分支与实际判据

后继 `M.new` 默认仍走原 network 分支，保留原 BridgeLab source-prefix 与同 UID、HasAuthority、有效 NetConnection 检查。只有 runtime 的可信本地配置明确 `authority_mode='standalone'`，并给出普通 Load 取得的实际 world directory、所选私有测试 Scripts 路径，才用单机分支；不从 MC guest request 信任这些配置。

`standalone_authority.read` 读取实际对象：

1. 真实同 UID PalPlayerController，`HasAuthority=true`、`IsLocalController=true`。pc 由原 helper 原生枚举匹配，不创建/替换 fake PC。
2. `GameplayStatics:GetGameState(pc)` 是当前 PC 所在 world 的 live authority GameState；实际 `GetWorldSaveDirectoryName` 精确等于 runtime 普通 Load 所选 world。
3. `PalUtility:GetOptionWorldSettings(pc).bIsMultiplay=false`；`KismetSystemLibrary:IsDedicatedServer(pc)=false`，该 world 无有 NetConnection 的远端 authority player。
4. `Kismet.IsStandalone`、`PalUtility.IsMultiplayer`、`GetNetMode` 的实际原值全部记录。若游戏内部用 local listen 实现单机，仍按真实 world 开关关闭/local authority/无远端玩家判据，不把 Steam 离线或缺 socket 当证明，也不伪造 `NM_Standalone`。未改任何 multiplayer/网络开关。

固定版本 SDK 给出上述全部 UFunction 签名和 `PalOptionWorldSettings.bIsMultiplay` bool；当前单机实例的返回形态由 runtime 普通 Load 确认。错误/缺失 getter 明确拒绝，不能填期望字段冒充观察。

确切 source refs 在 `work/palworld-live/lab/UE4SS_ObjectDump.txt`：65140–42 GetOptionWorldSettings（WorldContextObject@0、StructReturn@8），104424 bIsMultiplay@B8；85711–13 IsStandalone，85731–33 IsDedicatedServer；6454–55 IsLocalController；64399–64401 IsMultiplayer；65186–88 GetNetMode StrReturn；80813–15 GetGameState。它们是固定 server build 的反射签名定位依据，其 RVA 不能直接硬调用另一 client exe。相关 refs 已交 multiplayer/runtime provider；world reader/factory源码没有在本分支覆盖。

helper 在每次真实 context 中记录 authority，绑定当前 world/GameState 实例与实际 session 字符串。world 实例改变需重新实例化 helper，旧 WAL 保留；不能将旧 world/authority 的 paid setup ID 当当前单机 setup。session 允许实际空字符串，不编一个 fake server SID。

## 原正常消耗、工作与组件所属

local 分支只免“必须有远端 NetConnection”。所有其他真实条件仍保留：

* native PalPlayerState/guild，实际 `HasGuildPermission(actualUID,4)`，活着的真实 default character。
* `pc.Transmitter` 必须 live 且实际 Owner 正是该 PC；GetPlayer/GetItem/GetWorkProgress 组件 Owner 必须正是该 transmitter。若 SP 没有此 owned-transmitter 形态，先以其普通 Load 实据确定真实正常链，不拿 global transmitter 假装 player-owned Build/Work，不免费 Spawn。
* 真实 ItemChest recipe 15 Wood +5 Stone，实际科技解锁/未禁止；单机后继核实际 recipe work1000。没有材料/科技时正常采集/生产/解锁，不赋予材料或科技。
* 当前角色背包真实差额的普通 RequestMove、正常 consuming RequestBuild（`bNotConsumeMaterials=false`）仅一次、真正已注册 WorkId 的普通 RequestStartPlayerWork；没有 HP、progress、FinishWork、instantconstruct 写入。
* 原 WAL-before-attempt、真实 material delta、完成/空箱/owner/model/container/base-range 读取及保存登记验证要求不变。箱仍在全部实际基地范围 +10m 外；登记箱即使 released 也从一般 AI stock/organize 排除。

仅 runtime 普通单机 Load 取到 actualPalUid / actualWorldDirectory / actualWindowsScriptsDir / 可信 shared-root映射之后，可构造后继：

```lua
local helper=dofile(actualWindowsScriptsDir..'escrow_setup.lua').new{
  authority_mode='standalone',world_directory=actualWorldDirectory,
  scripts_dir=actualWindowsScriptsDir,json=existingJson,readers=existingReaders,
  root=actualWindowsExchangeRoot,durable_dll=actualWindowsWalDll,allow_build=true
}
-- 只按真实 shortage 正常取料，然后相同实例 preview/submit/start_work/observe。
local preview=helper.preview(actualPalUid)
```

以上变量没有默认历史 d817/world4123/basee9fe 值。本分支不创建实际 runtime 配置，不将旧专服 Wood8028/Stone218 当新单机库存。

## 与 runtime / multiplayer 必须对齐的现有依赖

| 部分 | 可复用 / 必须单机适配的事实 |
| --- | --- |
| Presence/登记 | `session-auth.lua` 已以 HasAuthority、真正 possessed Pawn、actual UID、实际 saved account/world/session 观察玩家，没有 NetConnection 硬门槛。可在 SP 正常 Load 观察后复用其原机制；原 MC world、playerdata、UUID、ledger保留，再正常登记实际 hostUID，不覆盖未完成旧交易 identity/receipt。 |
| File WAL | `exchange_store.lua` / `PalCraftExchangeDurable-v3.dll` 没有 PalServer exe/RVA pin，纯文件 durability 可复用。DLL要求 Windows盘符绝对路径的 startup `PALCRAFT_EXCHANGE_ROOT` 与 Lua root 相同；Mac host POSIX root 与 Wine盘符 root必须映射同一真实目录。CrossOver FlushFileBuffers/rename 运行行为尚未本分支执行，不能用虚假 durable.json 绕过。 |
| 当前 operator | 原 `escrow_operator.lua` / PS1 / BridgeLab-only script prefix仍是旧专服执行入口。本 SP successor应由实际 Mac私有测试包的正常 in-process game-thread 生命周期加载；不能改参数后调用旧专服脚本、开5090/512服务来让测试跑。 |
| 保存 / enroll | 当前 `escrow_enroll.py` 的 `lab_config` 固定 BridgeLab `SaveGames/0/.../Level.sav`，不能用于实际客户端 SP save root。后续要显式 actual SP installed-Level路径、world/UID/private-test-root 与 native setup authority/WAL配对，继续所有 actual Level model/concrete/module/container/成本/完整空箱/文件race 校验；不伪装/复制存档到Lab路径过 gate。此路径适配本候选未冒称实现。 |
| Save worker | 现 watch CLI 默认 REST8322保存回调；SP无需也不应因此启动专服 REST。正常 SP Save/Autosave后复用原 actual Level parser/witness（Runner支持 `save=None`），需要单机观察保存的 CLI/lifecycle映射；尚不能直接用旧 `--watch` 默认作为 SP流程。 |
| Boot/rearm | 现 bootstrap 写死 PalServer路径、Windows WMI/Task与专服 Level；新单机实际 process/world/load生命周期不能借用 ff0/40280旧证书。保现 full/empty/rearm语义，在已有机制上换实际 Mac/Wine load/save/process ports，无第二套 certificate层、无固定true verifier。 |
| MC→Pal produce | 当前 credit DLL硬钉 `D:/.../BridgeLab/.../PalServer-Win64-Shipping-Cmd.exe`、Server SHA6f929与Prepare/Commit/GameFree RVAs。它不能直接给 SP `Pal-Win64-Shipping.exe` 使用。需对应客户端真实 exe/ABI/Fingerprint 后继，保实际 saved MC debit、一次性permit、精确before/after、两保存屏障；未匹配时不进入MC扣料试验，不补送/免费spawn。 |
| 未来M01 | 原 network分支与多人脚本留档；以后明确多人授权时按实际网络/local-host语义和 A/B identity验证。此次只单机，不把无远端/单机通过当 M01通过。 |

## 检查与尚待实机的最小事实

只执行8项新增 authority 分支 fixture 回归及3个Lua语法检查，nice19串行约0.015秒，见 `authority-evidence.json`。覆盖真实 nil-socket local authority 路径、原 network socket不可免、internal-listen诊断不伪造、multiplayer world/dedicated/client/非local/remote player/错误world及 getter形态拒绝。旧 recovery/小屋/仓储矩阵未重跑；fixtures不是真实 PC/单机验收。

runtime 的下一次普通 Steam 单机 Load 足以确定实际UID/world/native mode和组件所属。然后原普通采集/科技/建箱/工作/保存链按实际条件推进。MAC paths、WAL行为、实际SP保存登记、当前client exe native credit/boot ports是独立明确待对齐项；本分支没有游戏、GUI、服务、新RPC或Saved读取/复制操作。
