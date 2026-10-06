# 托管材料机制有限收尾

本分支的 v3 托管适配器、真实 Level/NBT 见证器、单次 native credit、跨新 boot 的 rearm 和现有启动证据机制已保留。`runtime_verified=false`，没有宣称实机兑换或断电恢复通过。启动 getter 生命周期修复由 `00000000-0000-4000-8000-00000000000b` 的 `escrow-startup-repair/` 候选负责；本轮没有改它的文件，也没有操作服务、GUI、RPC 或实际存档。

## 本轮实际修正及证据

实际 `palcraft/runtime/evidence/next9_2-actual-loader-probe.json` 显示 manager 有效，loaded API/field 都为 true，但 `GetLoadedWorldSaveData` 与 `LoadedWorldSaveData` 对象无效，`uses_backup=true`、failed directory 为空。loaded 标志不能证明保存对象仍可解引用。

仅移除 `mcp/escrow_bootstrap.py` finalize/verifier 两处要求 `uses_backup=false` 的判断。该 bool 的真实含义仍未知，原始值继续保存在 observation。已有 OS/native boot 身份、实际 world/session、loaded/world-ready、failed-directory、sealed checkpoint、header/全 containers/交易槽位精确比较全部保留；重复 finalize 仍复用相同不可变证据。

额外 bool 无独立防重复作用：实际回退内容不同会被内容比较拒绝；与 sealed checkpoint 完全相同的副本具有相同材料状态。没有依据只因未知 flag 为 true 永久拒绝。

`bootstrap-backup-guard-evidence.json`：只执行两项新增针对性测试，串行 nice19，0.045 秒，通过。覆盖 true+精确匹配的签发/验证/重复 finalize，以及 true+header、containers、transaction_slots 任一错时拒绝。测试是 fixture 回归；旧矩阵未重跑，实机加载验收仍待 runtime。

## 最短正常兑换

前置只需已有实际生存成本的普通箱及其真实完成/登记。新的正常建箱和登记入口已由 exchange_v3 交给 runtime：真实扣 15 Wood + 5 Stone，不赠送材料，不把历史基地内且非空的箱当现成托管箱。保留同一已保存 model/concrete/container、真实所有权/位置与现有 reserved-ID 隔离。

* MC → Pal：正常扣除 MC 材料并保存 debit 标记 → 用该真实已落盘 debit 的一次性 permit 正常生成等量 Pal 托管材料 → 保存并核对托管 full Level → 正常 Move 到真实 Pal 背包 → 保存并核对同一 Level 的 escrow empty 和背包材料 → v3 completed 后释放箱。
* Pal → MC：正常 Move 真实 Pal 材料到托管箱 → 保存并核对同一 Level 的 escrow full 与来源槽 → MC 正常入账并保存 credit 标记 → 正常 Dispose 托管材料 → 保存并核对 escrow empty → v3 completed 后释放箱。

每次 native 效果之前持久记录 intent/attempt；结果丢失时先读回，不能盲目重试。正常消耗、两道实际保存屏障和 counterpart 材料状态是必要约束，不要求新增账号、额外客户端或另一套见证层。

## 最短恢复

1. 读取原 v3 WAL/lease，先恢复 held 箱隔离。已接受的 full/empty 保存见证继续有效，不删见证或重放已完成效果。
2. 不确定的 native 效果先用当前 canonical manager 重新解析 escrow/source/bag。精确 afterimage 可接回现有保存流程；部分或冲突状态保留待处理，不能再执行一次。
3. 只有真实新 Pal PID/creation、同 world、原操作之前的实际 checkpoint 被恢复，且有关 escrow/source/bag 全部精确回到 recorded beforeimages，才允许现有 rearm。沿用 generation、保留旧 attempt 历史、递增 attempt 并给新 RequestID。应先判定恢复，再让正常 autosave 覆盖旧 checkpoint。
4. 通过同一 full/empty 保存流程完成交易和释放。新 Lua epoch 或空箱本身均不足以证明可重试。

## 无需持续读取失效 save UObject 的路线

现有格式的最小兼容修复是 startuprepair 正在准备的方案：在实际 save UObject 有效期内复制真实 header/containers 为普通 Lua 值；待 world ready 后，重新解析实际 manager 交易槽位并核验已有 boot 身份链。本分支冻结的 Lua 不含该修复，不以 expected 数据冒充实际 observation。

若早采仍错过生命周期，持久原生态是每次重新 `PalItemContainerManager:GetContainer({ID=guid})`，再 `Get(slot)` / `GetSlotId` / `GetStackCount` / `GetItemId`，配合已注册 `PalMapObjectManager:FindModel`、实际模块与 concrete/container 绑定。新 boot 的 source/bag/escrow beforeimages、真实 loaded/world 和 PID/creation 才是有关材料恢复的必要证据。正常兑换无需持续解引用巨大 LoadedWorldSaveData；全世界其他容器/header 不是材料守恒的独立必要条件。若候选采用交易相关持久态替代全量早采，应由 startuprepair 明确列出既有接口调整，复用当前证据记录，无需新增证书层。

固定版本 dump：`LoadedWorldSaveData` UObject@0x118；`bIsUseBackupSaveData` bool@0x219；`GetLoadedWorldSaveData` 唯一 Object ReturnValue@0，RVA 0x01D85050；`IsLoadedWorldData` bool ReturnValue@0，RVA 0x0298E0F0。来源为 `work/palworld-live/lab/UE4SS_ObjectDump.txt`，imagebase 0x7FF7AA740000。

## 交接后的实际未完成项

* startuprepair 的最小早采/持久态候选在下一次必要正常加载中的真实验证；当前 probe 没有成功 loaded observation/恢复见证。
* runtime 的正常付费箱登记、真实 RPC/AI 排除路由和一件真实 MC debit 的 native produce。
* 两方向实际 full/empty Level 与 source/bag 保存闭环，以及一次现有交易的新进程恢复、不重复验收。

exchange_v3 的 store/current export、精确 lease_record 验证、AI exclusion、watcher 真实 verifier 接线已在源码交接，不再列为本分支缺失实现。运行操作者仍独占部署及实机窗口。无需为本轮 bool 修正单独重启或重复旧离线矩阵。

## 当前冻结指纹

| 文件 | SHA256 |
| --- | --- |
| `palcraft/server/exchange_escrow.lua` | `f90c866f1023a644faa3a9770e188bb40144d3ce2e30ce42f3cdde8c574cc6be` |
| `palcraft/mcp/escrow_bootstrap.py` | `8f987d208ab8f6d5578f089c19ec7518ebd21e8fe606c50bab23b56d1abcc4ad` |
| `palcraft/server/exchange_bootstrap.lua`（原 getter 版本） | `fea53f78988cad1e2c7f7b0472f68d5aef9d9f3d00f8e522ad5409282196620c` |
| `palcraft/mcp/escrow_rehydrate.py` | `36521bd2dc789971ace4f68a40e1d4e2e7da8928e6cab3ed2d219284db245cad` |
| `palcraft_escrow_credit_v1.dll` | `0260235fc9028a49f269fa450ec19886ff541c39f0e8983624d2219f4419748f` |
| `PalCraftEscrowBoot-v1.dll` | `8432074e272d77385b40271bb3c8524bf4185ef8015b8bfc1440a2f0cf871858` |

既有 92-case 全量离线记录及后续 5-case 聚焦记录保留；当前全部源码没有重新做全矩阵。静态 DLL/fixture 证据不替代 native produce、实际 loaded-schema 或断电恢复验收。

## 后续实机字段读取线索（ca47）

startuprepair 报告早采及实际 OS/native gate 已通过，1372 全 containers/slots、version/revision/Timestamp 与 sealed expected 完全匹配，transaction refs 为空。当前仍因 loaded header 缺 `real_date_time_ticks` 拒绝，尚未完成实际恢复验收。

固定 ObjectDump 126454–126456：`PalGameTimeSaveData.GameDateTimeTicks` 为 Int64@0x0，`RealDateTimeTicks` 为 Int64@0x8；126808：`PalWorldSaveData.GameTimeSaveData` 为该原生 struct@0x3D0，无 RawData 反射成员。旧 Lua 在同一 pcall 中先读 RawData，失败后未执行直接字段 fallback 并静默缺 key。`.sav` RawData 解码格式不等于实际反射结构。

已交 startuprepair 最小真实读取线索：在有效早采对象上直接取 `val(world.GameTimeSaveData.RealDateTimeTicks)`，检验整型并 `string.format('%d', n)`；字段读取失败需显式报错。UE4SS `push_int64property` 使用 `push_integer<int64_t>`，`LuaMadeSimple::set_integer(int64_t)` 直接调用 `lua_pushinteger`，无需单位转换。原局部 math 是 Kismet UObject，不能误用 math.type。没有用 sealed 值填 actual header，没有改严格 guard、本分支冻结 Lua或 repair 候选。

startuprepair 后续确认：Int64 直接读取候选已定稿，局部 Kismet math 已改名 date_math。唯一 actual-shape 回归令 RawData 访问抛错，旧 ca47 baseline 重现缺 key，新 candidate 通过，并用 123456789012345678（大于 2^53）核验精确十进制。全比较、Python 和实际 loaded 文件均未改；本分支未重跑其测试。此为 owner 报告的源码回归通过，下一必要正常加载的 actual finalize 仍待 runtime。
