import datetime
import hashlib
import json
import shutil
from pathlib import Path
from zoneinfo import ZoneInfo

root = Path(__file__).resolve().parents[3]
work = Path(__file__).resolve().parent / "f03-p01-source-audit-20261006"
assert not work.exists()
work.mkdir()
outputs = Path("/Users/PLAYER/Documents/Codex/2026-10-06/palcraft-input-performance/outputs")
install_work = Path("/Users/PLAYER/Documents/Codex/2026-10-06/palcraft-player-install/work")
installs = [p for p in install_work.glob("*/PalCraft") if (p / "PalCraft-Client").is_dir()]
assert len(installs) == 1
scripts = installs[0] / "PalCraft-Client/Pal/Binaries/Win64/ue4ss/Mods/PalCraftClient/Scripts"
sha = lambda p: hashlib.sha256(p.read_bytes()).hexdigest()
names = ["main.lua", "form.lua", "chunk_views.lua", "chunk_scheduler.lua", "chunk_geometry.lua",
         "companion_chunk_bridge.lua", "chunk_adapter.lua", "chunk_collision.lua", "models.lua", "palcraft-collisions.lua"]
pins = {n: sha(scripts / n) for n in names}
assert pins["main.lua"] == "5780a0f2e53f9b3b15ee3e59fd01591cb3fb81c31ce91915b2f949f49a0334b8"
(work / "source").mkdir()
for n in names:
    shutil.copy2(scripts / n, work / "source" / n)
flow_file = root / "work/minecraft-fusion/mac/drive_d/PalworldServer-LAN/PalCraft-Dev/bridge/operator-survival-flow.json"
flow = json.loads(flow_file.read_text())
a = next(s for s in flow["snapshots"] if s["label"] == "walk_start")["operator"]["input"]
b = next(s for s in flow["snapshots"] if s["label"] == "walk_finish")["operator"]["input"]
seq_ticks = (b["sequence"] - a["sequence"]) // 2
seq_seconds = b["unix"] - a["unix"]
peaks = []
for name in ["operator918-form-on-actual-state.json", "operator918-finite-precheck-abort-state.json", "operator918-form-off-final-state.json"]:
    p = root / "work/minecraft-fusion/palcraft/runtime/evidence" / name
    j = json.loads(p.read_text())
    s = j["state"].get("client-status.json", j["state"])
    metric = next(e for e in s["features"]["features"] if e["name"] == "client_world")["status"]["chunks"]["views"]
    epoch = j.get("observed_unix", s["unix"])
    peaks.append({"path": str(p), "sha256": sha(p), "local_time": datetime.datetime.fromtimestamp(epoch, ZoneInfo("Asia/Shanghai")).isoformat(),
                  "frame": s.get("frame"), "stats": metric["stats"], "pending": metric["pending"]})
ue = root / "work/palworld-live/research/ue4ss-2281fa31-LuaMod.cpp"
report = {
    "schema": "palcraft-f03-p01-source-audit-v1",
    "reviewed_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "scope": "source and existing finite records only; no game/RPC/probe/power/build/deploy",
    "selected_main": {"path": str(scripts / "main.lua"), "sha256": pins["main.lua"], "unchanged": True},
    "source_pins": pins,
    "UE4SS_source": {"path": str(ue), "sha256": sha(ue), "delay_registration_lines": [4396, 4540],
                     "ready_and_requeue_lines": [3939, 4156], "EngineTick_pre_hook": 4173,
                     "old_W01_log": "GameEngineTick found and LuaModImpl EngineTick prehook registered",
                     "new_Root_setting": "DefaultExecuteInGameThreadMethod=EngineTick at line69",
                     "new_Root_actual_hook_available": "not queried or assumed merely from the setting"},
    "movement_chain": {
        "main_delay_ms": 1, "main_lines": [393, 394, 403, 417, 464], "form_lines": [80, 102, 112, 120, 121],
        "order": "fresh input -> features/host gate -> normal form.tick if not held -> capture/publish",
        "AddMovementInput": "every eligible form callback with real focus=true, menu=false and nonzero direction; normalized diagonal, force=true",
        "speed_limits_cm_s": {"sneak": 130, "walk": 430, "sprint": 560},
        "physics": "original CharacterMovement integrates and consumes input; no callback-interval speed multiplier",
        "verdict": "no67ms delay in normal main/form; nominal next EngineTick/frame from1ms rearm, subject to game-thread stalls and eligibility; no confirmed speed/cadence defect to patch"
    },
    "finite_driver": {
        "path": str(flow_file), "sha256": sha(flow_file), "timer_delay_ms": flow["timer_delay_ms"],
        "move_calls": flow["move_calls"], "walk_actual_seconds": flow["walk_actual_seconds"],
        "horizontal_distance_cm": flow["walk_displacement_cm"]["horizontal"],
        "focus_both_false": not a["focus"] and not b["focus"], "same_input_generation": a["generation"] == b["generation"],
        "normal_snapshot_counter_ticks": seq_ticks, "input_clock_seconds": seq_seconds,
        "normal_snapshot_counter_advances_per_second": seq_ticks / seq_seconds,
        "interpretation": "67ms exceeds15FPS nominal66.67ms frame period and may skip the next frame; sparse scripted input is not sustained keyboard input; no keyboard-speed verdict"
    },
    "chunk_peak_evidence": peaks,
    "chunk_attribution": {
        "field": "client_world.status.chunks.views.stats.max_tick_ms; world.status.chunk_consumer is the same facade projection",
        "meaning": "lifetime max of entire Views:tick using its source clock, not native-only call or every-frame duration",
        "chain": "sole companion rearm50ms -> chunk_consumer.tick -> Bridge:tick -> Views:tick(default2ms/128) -> region Scheduler:tick/_step",
        "budget": "deadline checked between steps; a started geometry/material/sort/prepare/commit/unload step cannot be interrupted",
        "yields": "G already yields per block, tile, pack and collision batch/page; full builder is not one non-yielding loop",
        "prepare_boundary": "models.prepare/spawn_groups includes Lua material work, binary vertex/index writes, synchronous native() and result decode",
        "phase_for552": None, "phase_sample_available": False, "later_finite_boundary_peaks_ms": 188,
        "owner": "00000000-0000-4000-8000-000000000009 received exact fields, source pins and boundaries"
    },
    "later_profile_observation": {
        "local_window": "2026-10-06 09:42:24-09:42:31 Asia/Shanghai", "same_W01_window": False,
        "client": {"samples": 10, "callback_p50_ms": 66.6671022772789, "callback_mean_ms": 116.50505885481834,
                   "callback_max_ms": 559.3538880348206, "world_frame_max_ms": 400.0000059604645,
                   "main_total_stage_max_ms": 66.99999999997885, "form_active": False},
        "render_QPC": {"samples": 117, "loop_mean_ms": 8.565194, "loop_max_ms": 10.0517,
                       "work_max_ms": 1.2735, "camera_ws_frames": 0, "input_to_camera_samples": 0},
        "limit": "unmatched inactive-native window; zero latency samples means unavailable, not zero latency; not a gameplay benchmark"
    },
    "native_publication": {
        "worker_target_ms": 8, "movement_transport": "persistent80B binary, not100ms JSON heartbeat",
        "camera": "Lua game callback commits live112B prefix+scope; native sends changed cameraRevision;100ms compatibility export does not pace movement",
        "latency_metric": "newest input age at active camera commit; samples>=300ms excluded; not physical key-edge to displayed-frame latency",
        "transport_boundary": "synchronous ws.sendFrame may block shared worker; some mode/key sends precede writeSnapshot; active matched timing needed",
        "transport_patch": "none; existing supplied evidence does not establish it as observed cause; no arbitrary timeout/auth changes"
    },
    "after10_short_measurement": {
        "when": "2026-10-06 after10:00 Asia/Shanghai, runtime-owned window; not scheduled by this report",
        "keep": "same actual installed main/DLL/world; record actual frame cap/power state, do not change settings or forge focus/input/ACK",
        "duration_seconds": 12,
        "normal": "2s idle +3s real focused W-held +2s idle +3s ordinary yaw turn +2s settle, only with real focus available",
        "locked_alternative": "finite EngineTick/per-frame original AddMovementInput, not67ms; tag programmatic physics only, keyboard/F5/focus pending",
        "record": "actual focus/build/menu/forward + native seq/tick + main capture/form.frames + Pawn position/velocity + matched profile windows",
        "causal_checks": [
            "Snapshot advances but main/form/game-frame gaps: investigate serialized game-thread work.",
            "Main/form covers physics frames but sustained velocity low after acceleration: inspect actual movement/physics/network state.",
            "Native worker/network gaps and snapshot stalls: inspect synchronous transport, requiring active camera/nonzero samples.",
            "Time only the next normal chunk step by phase/section and Lua/IO/native boundary; lifetime max alone cannot identify552ms operation."
        ],
        "stress_or_matrix": "none; one short real sequence and one normal chunk phase observation"
    },
    "F03_acceptance": "pending real sustained normal-input measurement",
    "P01_acceptance": "pending matched active timing plus chunk phase attribution",
    "W01": "root confirms actual on/walk/full360/off passed in original scope; not downgraded by this audit",
    "source_fix": "none in owned main/form/controls; specific chunk-phase follow-up belongs to authorized chunk owner",
    "current72d_5780_3a1f_10_2_modified": False, "game_calls": 0, "power_changes": 0, "builds": 0
}
(work / "audit.json").write_text(json.dumps(report, indent=2) + "\n")
shutil.copy2(work / "audit.json", outputs / "f03-p01-source-audit.json")
coord = root / "work/minecraft-fusion/coordination/input_performance.json"
state = json.loads(coord.read_text())
state["updated_utc"] = report["reviewed_utc"]
state["F03_P01_source_audit"] = {"path": str(work / "audit.json"), "sha256": sha(work / "audit.json"),
                                "main_delay_ms": 1, "main_unchanged": pins["main.lua"], "chunk_owner_handoff": True,
                                "phase552_known": False, "source_fix": False, "F03_P01_accepted": False,
                                "W01_root_confirmed": True, "runtime_probe_or_power_changes": False}
temporary = coord.with_suffix(".f03p01.tmp")
temporary.write_text(json.dumps(state, indent=2) + "\n"); temporary.replace(coord)
print(json.dumps({"audit": str(work / "audit.json"), "sha256": sha(work / "audit.json"),
                  "main_delay_ms": 1, "source_fix": False, "F03_P01_pending": True}))
