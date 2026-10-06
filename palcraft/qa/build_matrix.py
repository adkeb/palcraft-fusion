#!/usr/bin/env python3
"""Regenerate the explicit acceptance contract; keeps source and gameplay evidence separate."""
import json
from pathlib import Path
HERE=Path(__file__).resolve().parent
TABLE='''S01|lead|正式服OFF、BridgeLab独立、原Steam bottle不动|baseline restart uninstall|production_off lab_boundary original_client_preserved|STATE为历史；须本轮进程端口快照与文件边界证据
S02|lead|正常生存、实际材料消费、不发免费物品、MC静音|baseline inventory survival_place exchange_import exchange_export|survival_mode no_item_grants mc_muted|旧Windows生存/静音证据不能替代当前Mac；兼容fixture不是正常材料消费
F01|input_performance|F5进入同一玩家的一套MC角色/第一人称/输入|baseline mc_enter|one_f5_one_transition exclusive_first_person first_person_visible|operator918真实programmaticnormalon/firstperson/hiddenweapons16，后APIwalk/360与normaloff恢复完成有限子集；physicalF5/keyboard/focus仍未证，presence-race反复disconnect诊断继续，不能把程序化setter等同物理输入通过。
F02|input_performance|F5切回Pal恢复原视角、移动、跳跃、HUD与武器|baseline pal_return|pal_state_restored pal_controls_restored hud_restored|operator918实际程序化offrequest1791248422→nexttick8423 activefalse/inputbuildfalse/gen61/hiddenweapons0/widgets0/transition4，Shot00016 root看原第三人称/红披风/装备恢复，与walkfinish XYZ完全相同无teleport；证明有限programmatic恢复子集，不代表physicalF5/焦点/长期稳定或完整F02。
F03|input_performance|自然行走/转向/跳跃/台阶，不慢走或双引擎争抢|locomotion solid_contact|walk_speed natural_motion step_jump|正常main1msEngineTick rearm+originalCharacterMovement walk430，67ms只属于旧有限脚本；16calls/2.5467s/4.18m稀疏API记录不能判当前键盘慢。正常focused持续行走/转向和手feel仍未证，不据此预设源码速度bug；已验W01不重测。
F04|input_performance|原斧头/锄头等工具不残留，退出恢复持有状态|baseline mc_enter pal_return|tools_hidden no_residual_mesh tools_restored|operator918真实on隐藏16武器，有限APIwalk/360后normaloff hiddenweapons0/widgets0且root实看第三人称原装备/披风恢复；有限programmatic隐藏/恢复子集已证，物理切换、长时不残留与全生命周期仍未证。
F05|input_performance|失焦/背包菜单输入释放，无误移动/挖放或F5双切|focus inventory mc_enter pal_return|focus_releases_input menu_blocks_actions no_double_toggle|焦点键沿修复在编写；静止状态不能代替主动释放输入验证
F06|entity_combat|两形态共享生命/受伤/死亡/重连，不切形态回血或双扣伤害|damage death reconnect|health_same_player damage_once no_toggle_heal shield_metabolism_same_authority death_respawn_persistent|first8.1实际严格绑定与Pal1/2370↔MC0.008438818点值已证明；完整F5/伤害/盾/饥饿/死亡/重连未证明，Mac锁屏阻塞输入，不作为游戏逻辑失败
W01|native_renderer|MC方块固定在Pal世界，360度转视角不跟屏幕漂移|world_anchor|actors_fixed_during_turn visual_world_alignment|已按原字面在current10.1/operator918普通OW构件/场景范围验收通过：实际APIwalk+360六ordinaryShot图由root全看，5same-lifetime ownedActor位置/旋转delta0，Palterrain/MCwood透视一致不随镜头漂移。物理F5/焦点、F03手感、W02纹理shader与X04维度不是本项前置条件。
W02|native_renderer|真实MC模型、每面纹理/UV/朝向/材质清晰且无crash|world_anchor world_replay|geometry_oracle per_face_textures native_visuals cold_load_safe|MC程序oracle只证算法；需Pal多面/楼梯/原木/炉/箱及冷加载现场
W03|native_renderer|实心MC块不被认成水、不游穿，台阶/半砖碰撞正确|solid_contact|solid_does_not_swim solid_blocks_motion shape_contacts|旧直走swim=false未覆盖贴MC墙；NoCollision视觉与权威碰撞通道须分别证明
W04|native_renderer|非整块、透明/裁切/水浸/连接/动态/箱子等模型正确|compat_models world_replay|noncube_visuals cutout_transparent connected_dynamic special_models|9.2源码caller与server_views已落、staging机械PASS未部署；实际非整块/透明/动态模型仍未证，fixture不得当原生引擎视觉通过。
W05|hud_stream|放置目标/合法面、挖掘进度、快捷栏和背包有正常MC指导|inventory survival_place survival_mine|hud_legible placement_guide mining_progress|HUD0/10.6未验像素边界仍留；旧Palcallback已真实恢复后正常Title/Quit退出，新25780onlyclientbootstrap/normalworldload-enroll在进行，尚无新MCbound/HUDpixels，不能延续“Lua永远停”或预先抬绿。
W06|hud_stream|挖掘/挥手/手持动画自然，无双重工具或诡异浮层|survival_mine inventory pal_return|hand_item_matches animation_natural no_double_hand|HUD单帧不证明连续动画；须视频或有序帧与selected/progress关联
I01|hud_stream|原版MC背包、快捷栏1–9/滚轮/拖放/堆叠可用|inventory|hotbar_selection inventory_drag_stack ui_click_alignment|旧WindowsGUI不能替代MacHUD坐标映射和实际点击
I02|integration_build|生存放置真正入世界并恰好消费材料|survival_place|placement_delta authoritative_block_set native_block_visible|旧legacy非碰撞按钮clear视觉失败未被首9.2实机替代；新caller/组合/staging仅源码证据，真实付费放置和原生可见性未证。
I03|integration_build|正常工具/硬度挖掘，方块消失且产出正确真实掉落|survival_mine|mining_duration authoritative_block_clear correct_drop native_block_removed|首9.2真实挖掘/掉落运行链未证；既有工具硬度/库存证据对完全未改组件可保留，新实际模型移除/掉落边界待一次真实流程。
I04|integration_build|走近掉落拾取，库存增加一次、实体消失无复制|pickup|pickup_delta drop_removed no_duplicate_pickup|既有v3按钮drop1→pickup1守恒可保留；首9.2真实物品模型/拾取尚未证，源码组合和staging不能继承新的物品运行边界。
I05|integration_build|原版2x2/工作台3x3配方正常，材料/输出守恒|crafting|craft_delta vanilla_recipe_ui result_in_inventory|旧button/pickaxe证据为历史；须当前配方参数/差额与GUI操作
I06|integration_build|炉子正常烧炼/燃料消耗/槽位/进度/输出持久|smelting reconnect|smelt_conservation furnace_ui burn_progress persists|旧8charcoal实测不能替代当前槽/燃烧/重连回执
I07|exchange_recovery|Pal↔MC材料兑换绑定本人身份、实际扣增、拒绝不足/满包|exchange_import exchange_export|exchange_conservation both_directions capacity_rejection identity_bound|旧v1ledger只证明金额，不证明新版身份/落盘恢复；pending不重复提交
I08|integration_build|箱子真实放置/存取/重开/重连持久，包与箱守恒|chest_store chest_reopen reconnect|chest_conservation chest_reopen_contents native_chest_interaction|旧15planks箱证据为历史；须当前玩家/箱槽前后与正常GUI
M01|multiplayer|多人Pal身份/MC UUID/背包/快捷栏/input独立|peer|two_real_pal_sessions unique_identity independent_inventory input_isolation|MP能力及原真实双Pal身份/背包/输入独立要求保持未来实际验；用户当前单机允许只改变本次执行profile，不允许forgeB或把单玩家映射/fixture当双人通过。
M02|multiplayer|世界/箱子共享，同步挖放可见，竞争取物不复制|peer|shared_blocks shared_chest race_conservation|历史MCpeer取箱15→14且主包不变只为局部，不证两Pal同时可见
M03|multiplayer|认证/断线会话/目录隔离，不能控制他人或他服|peer reconnect|authenticated_binding unauthorized_rejected bridge_dirs_isolated|已证明normalrestore/currentrealSPpresence下可信管理员备份原registry，仅4123/D817→actualhost1唯一1row，MCeddb/name保、WAL/journals不变，再原10.4 SessionEnrollment正常签名verifiedtrue；只闭合该合法身份连续性与当时fd3a/gen1签名。现在freshRealmgen2/423a（同Win1760FILETIME）firstbind在进行，旧签名不等当前SID/ACK/完整session认证通过。
R01|integration_build|重连/后端重启保持角色/生命/库存/箱子/世界|reconnect restart|reconnect_identity inventory_persisted chest_persisted world_persisted|新增旧SPcallback实际恢复后normalReturnTitle/Quit/exit0、停机稳定Saved165files/22552445B copy/hash窄scope已证；最近21:21autosave，不宣称最新运行内存已写盘。新25780bootstrap/onlyclient启动未完成freshMCbound/pixels，完整R01仍未过；旧角色/tx17ACK历史保留。
R02|exchange_recovery|跨引擎事务断电/重复/重启/离线恢复恰好一次|offline_recovery restart|durable_receipts crash_window_tests replay_idempotent disconnect_resume ambiguous_hold legitimate_activity_progress|恢复模块正编写；旧prepared/needs_recovery不能当完成或重复扣增
R03|input_performance|持续正常玩耍稳定，不回标题/崩溃/自动退出形态|sustain|sustained_session no_crash no_uncommanded_transition|13:17LuaStopped不再当当前事实：13:28/29及13:31callback真实恢复，随后原引擎正常Title/Quit退出；这纠正该 frozen时期但不能清除反复disconnect/长期稳定失败。当前25780normalbootstrap不是连续可玩证明。
R04|native_renderer|冷加载/重放/卸载不留幽灵碰撞或重复模型，队列收敛|world_replay restart|cold_replay replay_no_duplicates queue_eventually_drains remove_unloads|实际10.1同PID重连旧context正常清理/新worldview2恢复，pending0/errors{}且无旧lifetime/reset_error；只证明此次cycle恢复，完整卸载/幽灵碰撞/模型去重及defaultprepare增量仍未证。
P01|input_performance|Mac真实游玩不卡，帧耗时/输入/HUD延迟可接受|locomotion survival_mine sustain|frame_budget input_latency hud_latency no_visible_stutter|当前日间真实MacAC2/battery0/autoSMC0/0/nominal与5090CPU100/boost2/GPU575/SYS2SYS3Smart+NVMLauto0系统已回读，日间无3600cap；freshlive游戏FPS未验、MC已停，不把旧5090/nightprofile或inactive0samples当当前性能/0latencypass。historicalcommit432ms边界记录非DLL因果或当前步行同窗。
P02|chunk_scaling|1000/10000真实model世界有界调度/内存/卸载和游戏性能|scale_1000 scale_10000|real_scene_1000 real_scene_10000 bounded_schedule memory_plateau game_fps_at_scale|新增offline合批吞吐不能冒称现场FPS，28块不能证明大规模可玩
D01|player_install|普通玩家可无作者路径安装，明确依赖/授权/版本|install|clean_install dependencies_checked no_hardcoded_dev_paths|中文root普通MacofflineStandalone原角色normalworldload已实际到MainWorld/initializedlocalAuthority，原instance/level/guild/bag连续性范围已证；完整普通player组合MC/HUD/合法绑定仍待同normalflow，不把role恢复当全部安装/featurepipeline完成。
D02|player_install|可配置远端服/身份并启动，断线有可理解提示|config|configure_remote launch_healthy actionable_error|当前不是13:17LuaStopped静态状态：旧实际callback13:28/29连续fresh、7082frame/6750ticks→root13:31frame7089已恢复，随后normalReturnTitle/Quit成功、Shipping20339/Win1792exit0/HOST0无forcekill。现managed25780onlyclient单机bootstrap/normalworldload-enroll在进行，新MCbound/pixels/game_ready未证。
D03|player_install|卸载保留存档并恢复原设置/文件，不碰原bottle|uninstall|uninstall_receipt saved_data_preserved original_settings_restored|须安装/卸载前后hash与拥有文件清单；禁止用生产save测试
D04|integration_build|当前玩家包含本轮构件/版本/hash/配置文档，构建可复现|install|package_hashes build_reproducible current_artifacts|10.2/presenceguard/all5b9b部署、中文安装和VCexit0/5DLL匹配证据可复用；MC60/HUD30已实际配置但Palprimary228exit53，无RootScene/autoACK，完整当前运行包未过。
X01|world_compat|水/熔岩/水浸流动跨引擎可见，游泳/伤害/更新正确|fluid|fluid_visual flow_updates real_water_swim lava_damage|9.2 fluid caller和server_options/server_views已落、Lua factory组合PASS仅native/engine fixture；真实水/流动/游泳/伤害未证，staging不构成实际流体通过。
X02|world_compat|红石按钮/门/灯/活塞等状态和实体变化正确同步|redstone|redstone_state piston_move native_dynamic_render persistent_state|原版后端计算不等于Pal看到非实心红石/动态外观或能交互
X03|world_compat|作物种植/生长/成熟/采收保持材料/阶段/持久|crops|crop_stages crop_interaction harvest_conservation crop_persistence|旧bridge缺非实心作物/年龄状态，需原生阶段和生存采收
X04|dimension_travel|真实维度/传送门出入，身份/坐标空间/回程/持久正确|dimension|actual_dimension dimension_state return_origin dimension_persistence|跨机travel原行mirror+3ops+installed receiver构造loopback PASS、14真实Lua模块clientfactory组合PASS均仅离线边界；9.2未部署，真实双向TP/非OW cold reconnect未证，初始OW条件→travel启动循环待增量修。
X05|entity_combat|MC/Pal实体可见移动、双向战斗、生命/死亡/掉落守恒|combat damage death|entity_visible bidirectional_damage hit_once health_death_loot|旧MobWar有GTAperson/car语义；Paladapter未证，协议空壳不算战斗
X06|entity_combat|投射物/爆炸跨引擎只命中一次，破坏/来源/伤害正确|combat|projectile_bridge explosion_blocks damage_source_authoritative|发proj事件不证明Paltrace/伤害/爆炸落地
A01|integration_build|既有AI建筑/材料/科技/基地和仓储能力整合不回退|offline_ai|ai_survival_consumes ai_owner_bound storage_guarded rpc_reachable|A01四原checks按既有AI整合无回退目标在明确scope已验收通过：当前4fresh读+exact未改paidbuilder/owner组合，当前两ordinary箱sealedplan一次apply41/41/全48slotguardedreadbacks闭合。Move即时Berries202正确、later201按同6f929原生code+asset+rate/time自然腐败归因保留；原始later不是全量相等，当前倍率/每expiry hook未新测，不要求永恒食品库存。
'''
VISUAL={
'F01':'first_person_visible','F02':'pal_controls_restored hud_restored','F03':'natural_motion step_jump','F04':'no_residual_mesh','F05':'focus_releases_input menu_blocks_actions','W01':'visual_world_alignment','W02':'per_face_textures native_visuals','W03':'solid_blocks_motion shape_contacts','W04':'noncube_visuals cutout_transparent connected_dynamic special_models','W05':'hud_legible placement_guide mining_progress','W06':'hand_item_matches animation_natural no_double_hand','I01':'hotbar_selection inventory_drag_stack ui_click_alignment','I02':'native_block_visible','I03':'mining_duration native_block_removed','I05':'vanilla_recipe_ui','I06':'furnace_ui burn_progress','I08':'native_chest_interaction','M02':'shared_blocks shared_chest','P01':'no_visible_stutter','D02':'actionable_error','X01':'fluid_visual','X02':'native_dynamic_render','X03':'crop_stages crop_interaction','X04':'dimension_state','X05':'entity_visible'}
AUTO={'F06':{'health_same_player':['passive_probe']},'S01':{'production_off':['passive_probe']},'F01':{'one_f5_one_transition':['passive_probe'],'exclusive_first_person':['passive_probe']},'F02':{'pal_state_restored':['passive_probe']},'F03':{'walk_speed':['passive_probe']},'W01':{'actors_fixed_during_turn':['passive_probe']},'W03':{'solid_does_not_swim':['passive_probe']},'I02':{'placement_delta':['inventory_arithmetic']},'I04':{'pickup_delta':['inventory_arithmetic']},'I05':{'craft_delta':['inventory_arithmetic']},'I07':{'exchange_conservation':['exchange_arithmetic']},'R02':{'durable_receipts':['exchange_arithmetic']},'P01':{'frame_budget':['passive_probe']}}
HIST={'F02':['mac/form-restored.json'],'F03':['mac/move-probe-verified.json'],'W02':['coordination/lead-evidence/native-world-v3-reviewed.png'],'W03':['graphical/v9-standing-slab.json','graphical/v9-standing-stairs.json'],'I03':['graphical/v12-pickaxe-mined-stone.json'],'I04':['graphical/v13-drop-before-pickup.json','graphical/v13-drop-after-walk.json'],'I05':['graphical/v10-crafting-result.json'],'I06':['graphical/v13-furnace-processing.json','graphical/v13-after-smelting.json'],'I07':['graphical/mc-00000000-0000-4000-8000-000000000024.json'],'I08':['graphical/v12-chest-reopened.json'],'S02':['graphical/v13-final-runtime.json']}
J='palcraft/mc/src/main/java/dev/rehan/passthrough/';K='palcraft/mc/src/client/java/dev/rehan/passthrough/client/'
SRC={'S01':[('palcraft/client/main.lua','Use the isolated test client'),('palcraft/server/main.lua','Lab paths only')],'F01':[('palcraft/client/form.lua','SetIgnoreMoveInput(true)'),('palcraft/render/controls.cpp','VK_F5')],'F02':[('palcraft/client/form.lua','M.speed')],'F03':[('palcraft/client/form.lua','MaxWalkSpeed')],'F04':[('palcraft/client/form.lua','M.weapons')],'F05':[('palcraft/render/controls.cpp','GetAsyncKeyState')],'W01':[('palcraft/client/models.lua','origin.X+x*100')],'W02':[('palcraft/client/models.lua','CreateMeshSection'),('palcraft/client/model_geometry_v2.lua','')],'W03':[('palcraft/server/main.lua','boxes')],'W04':[('palcraft/client/models.lua','special_model_required')],'W05':[(K+'PlacementGuide.java',''),(K+'PlayFeedback.java','progress'),('mac/hud_overlay.swift','')],'W06':[(K+'FrameExporter.java','')],'I01':[(K+'ClientInput.java','')],'I02':[(J+'WorldBridge.java','onBlockChanged')],'I03':[(K+'ClientInput.java','')],'I04':[(J+'WorldBridge.java','reportDrops')],'I05':[(K+'ClientInput.java','')],'I06':[(J+'WorldBridge.java','inspectAt')],'I07':[(J+'ResourceExchange.java',''),('palcraft/server/exchange.lua','')],'I08':[(J+'WorldBridge.java','blockinspection')],'M01':[(K+'HostLink.java','')],'M03':[(K+'HostState.java','')],'R01':[(K+'HostLink.java','')],'R02':[(J+'ExchangeRecovery.java','applyOnce'),(J+'ExchangeJournal.java','')],'R03':[('palcraft/client/main.lua','connection-history.ndjson')],'R04':[('palcraft/server/main.lua','signature')],'P01':[('palcraft/client/main.lua','')],'X01':[(J+'WorldBridge.java','solidForHost')],'X02':[(J+'WorldBridge.java','')],'X03':[(J+'WorldBridge.java','')],'X04':[(J+'Nether.java',''),(J+'DimensionTravel.java','')],'X05':[(J+'MobWar.java','nearestProxy')],'X06':[(J+'WorldBridge.java','reportProjectiles')],'A01':[('palcraft/server/bridge-main.lua',"method=='storage_apply'"),('palcraft/mcp/ai_tools.py','palworld_ai_build')]}
USER={'F01':'00000000-0000-4000-8000-000000000005','W05':'00000000-0000-4000-8000-000000000005','W03':'00000000-0000-4000-8000-000000000005','F03':'00000000-0000-4000-8000-000000000007','W01':'00000000-0000-4000-8000-000000000007','F04':'00000000-0000-4000-8000-000000000008','P01':'00000000-0000-4000-8000-000000000008','W06':'00000000-0000-4000-8000-000000000006'}
UNIMPLEMENTED={'F06','P02','D04','X01','X02','X03','X05','X06'}
cases=[]
for line in TABLE.splitlines():
 i,owner,req,phases,checks,gap=line.split('|')
 cases.append({'id':i,'owner':owner,'requirement':req,'phases':phases.split(),'required_checks':checks.split(),'visual_checks':VISUAL.get(i,'').split(),'check_sources':AUTO.get(i,{}),'current_gap':gap,'initial_status':'unimplemented'if i in UNIMPLEMENTED else 'unproven','source_evidence':[{'path':p,'contains':m}for p,m in SRC.get(i,[])],'historical_evidence':HIST.get(i,[]),'requirement_origin':{'kind':'user_message','id':USER[i]}if i in USER else{'kind':'delegated_player_goal','thread_id':'00000000-0000-4000-8000-000000000004'}})
PHASES='''baseline|Pal基线≥3秒；取身份/生存/静音/原武器/视角/HP；核对lab与生产OFF
mc_enter|一次F5进入MC静止≥3秒；输入锁/camera/transition/工具隐藏/HP
world_anchor|站定慢转360度和抬低头≥5秒；有序画面+Actor世界变换
locomotion|直走2.5秒、转向/跳跃；速度/输入/帧耗时
solid_contact|顶同一墙≥3秒，再半砖/楼梯；swim/mode/路径，不造水
inventory|E开包、1–9/滚轮/拖放，权威snapshot
focus|菜单与AltTab释放输入；失焦不注入动作
survival_place|存量材料放1块，参数player UUID/item/count/at，before/after库存与块
survival_mine|正常工具挖掉同目标；耗时/进度/clear/真实掉落
pickup|走近拾取；前后本人库存与实体ID/数量
crafting|已有材料原版2x2/3x3；配方、前后差额
chest_store|已持物存箱；玩家库存+箱槽前后守恒
chest_reopen|关闭重开同箱；contents一致
smelting|已有输入/燃料烧炼；等待同时执行sustain，槽/进度/输出
exchange_import|一笔Pal→MC；保留相同事务ID双边ledger，pending不重提
exchange_export|一笔MC→Pal；不足/满包无条件则留未证明，禁止grant
pal_return|一次F5恢复Pal；与baseline比视角/工具/HUD/input/HP
reconnect|独占GUIowner正常重连，前后本人身份/生命/包/箱/世界
sustain|连续≥5分钟正常玩耍；状态/帧耗时/非预期transition/错误
peer|两实际Pal会话同时绑定；独立包/input、共享块/箱，竞争守恒
restart|须独立服务租约；只重启lab/共享MC，成组保留交易资料
world_replay|coldload/重放存量世界；看队列稳定而非终点瞬时pending
compat_models|既有或正常材料看特殊/连接/透明/动态模型，算法独立
 damage|两形态同权威生命，实际两边伤害只结算一次
 death|实验副本或正常lab死亡/重生；明确恢复边界，禁止生产save
 offline_recovery|owner离线故障窗口测试；不杀共享服
 scale_1000|1000真实model，离线吞吐与现场FPS分记
 scale_10000|10000真实model，内存/调度/卸载/现场帧耗时
 install|干净临时玩家目录安装；回执+构件hash，不碰原Steam bottle
 config|非作者服务器/身份配置、错误反馈与启动检查
 uninstall|仅删manifest拥有文件；前后save/原设置hash保持
 fluid|正常水/熔岩/水浸，流动/伤害/正确游泳
 redstone|按钮/门/灯/活塞原版状态与Pal外观/实体同步
 crops|种植/成长/采收，材料守恒和阶段状态
 dimension|真实dimension ID与出入/坐标空间/回程持久
 combat|两边实体移动/攻击/命中/生命/掉落/来源
 offline_ai|隔离AI建筑/仓储回归，禁止生产'''
policy={'walk_speed_cm_s':[380,560],'actor_drift_cm':.5,'mean_fps_min':45,'frame_p95_ms_max':33.3,'frame_max_ms':250,'minimum_frame_samples':300,'sustain_seconds_min':300,'queue_drain_seconds_max':15,'input_latency_p95_ms_max':120,'hud_latency_p95_ms_max':150,'policy_origin':'提出的玩家级验收预算；用户要求不卡/自然，未指定数值。构建冻结前可调整并记录；离线耗时绝不当真实FPS。'}
environment={'graphics':'Mac CrossOver PalCraftLab only','backend':'5090 BridgeLab UDP8321; shared MC25567/guest25599/HUD25603','production':'OFF; production saves forbidden','audio':'MC master_volume=0','remote_cpu_max_percent':30,'remote_turbo_enabled':False,'remote_gpu_power_limit_w':400,'pal_fps_cap':15,'mc_fps_requested':15,'mc_fps_actual':10,'hud_fps_cap':10,'mac_fan_max_rpm':3600,'fan_ceiling_scope':'night_only','night_hours_local':'00:00-10:00','timezone':'Asia/Shanghai','mc_client_simulation_distance_actual':12,'mc_server_simulation_distance_actual':4,'day_mac_fan_control':'automatic_no_3600_cap','day_windows_fan_control':'preserve_verified_SYS2_SYS3_Smart_and_GPU_NVML_policy0_no_fan_switch','day_plan_prepared_not_activated':True,'full_load_thermal_proven':False,'windows_universal_3600_clamp':False,'mac_low_power':True,'origin':'Main coordinator relayed direct user environment requests; preserve caps and record measured environment, never raise them for FPS tests'}
m={'schema_version':1,'environment_contract':environment,'active_profile':json.loads((HERE/'active-profile.json').read_text()) if (HERE/'active-profile.json').exists() else {'profile_id':'normal','performance_qualification_allowed':True},'objective':'完整MC×Pal迁移达到面向玩家水平','status_vocabulary':{'proven':'已证明：本轮完整对应证据','unproven':'未证明：含源码/历史局部证据','contradictory':'矛盾或本轮失败','unimplemented':'跨引擎链路未实现/缺集成证据'},'policy':policy,'evidence_rules':['源码/旧STATE/旧v13ZIP/单帧/owner声明不能自动放绿','MCoracle算法和Pal现场分开','每run冻结source/build，记录时间、owner、phase、UUID、事务ID、artifact hash','缺前后/失败/冲突不得用空值当pass','连贯流程复用证据；实现分支无需等QA单测','正式服OFF；生产save与原Steam bottle禁止访问/改动','配置rollback不等于数据rollback；WAL/receipt/双边库存/世界成组保留，不能只拷DLL回滚数据'],'phases':[{'id':line.split('|')[0].strip(),'action':line.split('|')[1]}for line in PHASES.splitlines()],'cases':cases}
accepted_path=HERE/'accepted-case-evidence.json'
if accepted_path.exists():
 for ci in cases:
  decision=json.loads(accepted_path.read_text()).get('cases',{}).get(ci['id'])
  if decision:
   ci['status']=decision['status'];ci['accepted_scope']=decision['scope'];ci['accepted_case_evidence']='palcraft/qa/accepted-case-evidence.json#'+ci['id']
partial_path=HERE/'case-check-evidence.json'
if partial_path.exists():
 for ci in cases:
  decision=json.loads(partial_path.read_text()).get('cases',{}).get(ci['id'])
  if decision:
   ci['checks_proven']=decision['checks_proven'];ci['checks_partially_proven']=decision['checks_partially_proven'];ci['scope_status']=decision['scope_status'];ci['full_case_accepted']=decision.get('full_case_passed',False);ci['case_check_evidence']='palcraft/qa/case-check-evidence.json#'+ci['id']
(HERE/'matrix.json').write_text(json.dumps(m,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'matrix_cases':len(cases),'phases':len(m['phases'])}))
