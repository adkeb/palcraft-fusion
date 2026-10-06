# Mac 单机 credit / Save / enroll 后继：运行交接

这份后继在原 v3 的 WAL、MC已保存收据、一次性permit、exact native readback、full/empty Level见证上接单机。旧网络源码与 Server DLL保持原样。此分支没有启动游戏、RPC/5090、修改UID/物资/HP/科技/timer，也没有读取/修改游戏Saved。

## 已有实际接口事实

正常 CharMake/确认 Yes 生成真实 host `00000000-0000-0000-0000-000000000001`，已 initialized/local controller/authority；它不是预填的假默认UID。所选世界 `AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA`，实际private UserDir 和 Level路径来自 runtime `actual-host-birth-and-owned-SaveRoot.json`。原33 D817→host1的正常迁移由runtime负责，迁移未实际完成前，本包不造 alias/不声称MC ready。

实际 client exe：e590b5e7bfaa3fea40fab1a02cc72c8fc5fd6f8631ef2308e95ac56c25195837，161802312B，AMD64，ImageBase140000000，Stamp6aa377c1，SizeImagea011000；path/native owner各已核actualinstalled与隔离cache同SHA。本分支只离线读取该cache。

完整函数对应（屏蔽外部call/RIP32重定位，内部branch/ABI结构常量不屏蔽，再核client pdata完整边界）：

| 函数 | Server原RVA | client实际RVA | 完整体 / 保留字节 | 唯一完整匹配 |
| --- | --- | --- | --- | --- |
| Prepare | 2e6c180 | 2fc1400 | 1444 /1300 | 1 |
| Commit | 2e60400 | 2fb5680 | 1274 /1138 | 1 |
| GameFree | 32a0700 | 33f9750 | 52 /40 | 1 |
| Container lookup | 3034120 | 3189af0 | 78 /74 | 1 |

见 `client-function-match.json` 和每函数server/client完整asm。新 native ABI仍 SlotId20、payload48、produce88、body144、wire208、permit128；不把旧server RVA直接写到client。

## 新DLL与全部失败保护

`PalCraftEscrowCredit-client-v1.dll` 用已就位Mac Zig0.15.2、nice19、j1、原Win64 raw C/fastcall参数编译；没有MSVC STL/RTTI/EH/UE4SS C++库边界。旧 `palcraft_escrow_credit_v1.dll` SHA0260235f… 未变。

* `palcraft_escrow_credit_v1` 仍先核实际运行exe与trusted `PALCRAFT_PAL_EXE` 指向同一文件、完整e590 SHA、client PE和完整内存函数指纹。Wine不同盘符alias只有实际非零file identity相同才接受，不能靠修改字符串放宽。exe SHA每process缓存一次，code/object/slot守卫每次保留。
* 输入/输出改trusted `PALCRAFT_RPC_ROOT` 的真实Windows绝对目录，没有专服D:/BridgeLab默认路径。Mac/Wine的实际映射由scope校验。
* 原实际MC saved-debit UUID/world/marker/SHA证明与128B一次permit，非replace claimed、attempt-before-effect、真实空slot/descriptor/item/dynamic ID、prepared record/target/from/beforeimage、Commit一次与精确readback全部不删。
* CDO `PalItemUtility` 用 valid判断，不再错误排除Default__；`CreateLocalItemSlot(WorldContext,FName,int)`签名已固定dump44508–44512证实，仅作瞬态descriptor，不是免费持久容器或玩家包staging。
* 新 `palcraft_escrow_client_identity_v1` 只在同exe/code gates过时写真实Win PID/creationFILETIME/observedUnix/thread。没有Actor、inventory或save操作。

produce-only prepared.from convention仍由runtime一件真实MC已扣料实验验证；准备不匹配会在Commit前拒绝，permit不重用，不补送材料。

## 现有模块如何接通

部署成对source至实际私有客户端的in-process authority Scripts，替代该测试包对应模块；原源码留档不改：

* `standalone_authority.lua` + `escrow_setup.lua`（59/49 sourcepair）：真实local authority/worldOFF/非dedicated/无remotePC，保正常15W5S、tech、work1000、actual owned transmitter/组件和WAL。
* `exchange_escrow.lua`：原状态机/隔离不变，backend在每个effects前核同实际host/world，credit RPC根改实际scope。
* `exchange_v3.lua`：原WAL/store/receipt协议不变，Standalone只用当前actual client process binding，不借旧Server certificate/ff0/PID。native RequestID算法保留。
* `standalone_service.lua`：加载新DLL readonly identity，在原file WAL中持久绑定真实process。boot GUID由actualPID/FILETIME/world派生，mod reload不会假变boot。只在正常game-thread生命周期处理save command，实际 `GetSaveGameManager(localPC):StartWorldDataAutoSave()` + `StartLocalWorldDataAutoSave()`；不是REST、Task或WMI。
* `standalone_exchange_runtime.lua` 薄组合：service→只有真实paid config存在才v3构造/tick，向owner暴露原setup接口；缺config不会创建容器或免费物资。

runtime普通Load/factory构造一次、在已有game-thread tick中调用组合即可，不开启新transport/专服。它的scope/DLL/root参数由可信本地配置传入，不能从guest包信任。PC.Transmitter/其Owner及各组件所属还需实际Load确认；之前记录只有transmitter名字，不能凭PersistentLevel名虚构Owner。

## Mac实际路径、保存与登记

`scope-template.json` 仅填已有真实host1/world/privateUserDir，未观察的Wine/mappedRoot字段null且configured=false。本分支未安装live profile或承诺迁移完成。

runtime正常保存并完成其原33角色迁移后，填实际profile：Wine prefix、Windows actualexe/RPC/WAL/scripts/DLL路径和对应Mac物理路径。`escrow_standalone.load_scope` 检查每个实际drive mapping指向同物理目录/文件、actualexe e590、所选privateUserDir内同world installed Level；不拷Saved到Lab0、不fallback到生产/512。

Python MCP部署原依赖和这些后继：

* `escrow_standalone.py` 是path/native-authority/process-binding ports。
* 后继 `escrow_enroll.py --standalone-scope <actual-profile>` 不要求server-root，继续所有原成本/完整durable setup revisions、native host/world、实际已安装Level model/concrete/module/container/capacity/guild/position/buildUID、空槽和file race检查。config写真实Windows DLL路径，并保native-credit/daily-isolation runtime未验标志。
* 后继 `exchange_v3.py` 只增加可选boot_path port，默认网络流程不变。`escrow_standalone_watch.py` 使用该原Runner、actualLevel parser、MC NBT+oncepermit和同exact current lease publication；save回调只发既有filecommand给inprocess正常Save API，约1s tick，无REST/WMI/Task。

执行仍由runtime solelease，示例均指实际已有Mac Python/vendor/profile：

```sh
python escrow_enroll.py --standalone-scope ACTUAL_PROFILE --root ACTUAL_MAC_EXCHANGE_ROOT --level ACTUAL_PRIVATE_LEVEL --setup-id ACTUAL_PAID_SETUP_ID --durable-dll ACTUAL_MAC_WAL_DLL --credit-dll ACTUAL_MAC_CLIENT_CREDIT_DLL --parser-vendor ACTUAL_PATCHED_VENDOR --lab-candidate
python escrow_standalone_watch.py --scope ACTUAL_PROFILE --parser-vendor ACTUAL_PATCHED_VENDOR --watch
```

一root只有一个Save/witness执行者。native Save返回/async callback只是request诊断，只有文件force/read/race校验后的实际Level内容能推进full/empty。SP读大loadedSave UObject已释放无关：持久manager读当前slots，磁盘parser读实际已保存Level。

## 最短实际一件闭环与恢复边界

1. 正常Load实际host1、完成runtime正常角色恢复/MC原world+eddb UUID+ledger保留与正规绑定；旧journal key/收据不改。验证readonly client identity/code支持，不提前进入MC扣料。
2. 原setup正常取料/tech/ground/15W5S consuming build一次、普通work1000、Save→实际private Level→normal enroll。不把旧非空基地stock箱当escrow。
3. 原MC UI数量设1，Pal Wood1→MC oak_log1，真实full-save/MC credit receipt/Pal dispose/empty-save/released闭环完成，再同oak_log1正常MC debit→一次permit→client nativecredit→full-save→真实bag→empty-save/released。不创建假的MC intent/result/alias。
4. 每阶段保存仍核同Level source/bag归属、exact escrow slot、lease/generation/revision/phase与整行current。unknown/partial effect保留原attempt，不盲重试。

当前client actual process binding不是full-world rehydration certificate。若真正process改变且有未见证native effect，既有Runner会识别changed boot，保留原checkpoint，不发Save覆盖/不rearm；真实已保存afterimage可正常接回见证。受控rearm仍只接受现有 `escrow_rehydrate` 的真new-process+完整实际checkpoint/beforeimages verifier，未提供时保持待恢复，不能把binding/native_code_matched当fullworld true。这保留断电防重复保护；没有新增第二套证书或fixedtrue verifier。

## 检查范围

已做唯一full-function client匹配、Mac独立DLL build+PE/import/export检查、8个authority新fixture、5个path/physical mapping/currentprocess durable/stale拒绝新fixture和新增Lua/Python syntax。没有旧矩阵、游戏调用、timer fixture、5090、实际Saved读写或生产访问。本包runtime_verified=false；runtime下一唯一窗口负责实际code识别、保存/登记和一件nativecredit试验。
