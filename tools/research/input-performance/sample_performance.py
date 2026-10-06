#!/usr/bin/env python3
"""Read-only PalCraft sampling. Does not send RPC, alter input, or control apps."""
import argparse
import datetime as dt
import json
import math
import statistics
import struct
import subprocess
import time
from pathlib import Path

INPUT = struct.Struct("<8sQQdqqIiiIIIQ")
CAMERA = struct.Struct("<8sIIdddddddffffff")
FILES = ("client-status.json", "client-performance.json", "render-status.json",
         "render-performance.json", "controls-performance.json", "input-state.json",
         "mac-hud-status.json")
DEFAULT_BRIDGE = Path("/path/to/workspace/work/minecraft-fusion/mac/drive_d/PalworldServer-LAN/PalCraft-Dev/bridge")


def read_json(path):
    try:
        info = path.stat()
        value = json.loads(path.read_bytes())
        return {"mtime": info.st_mtime, "value": value}
    except (OSError, ValueError):
        return None


def distribution(values):
    values = sorted(v for v in values if isinstance(v, (int, float)) and math.isfinite(v))
    if not values:
        return None
    return {"samples": len(values), "mean": statistics.fmean(values),
            "p50": values[math.ceil(len(values) * .5) - 1],
            "p95": values[math.ceil(len(values) * .95) - 1],
            "max": values[-1]}


def summarize(samples):
    statuses = []
    unique = {name: [] for name in FILES}
    for row in samples:
        for name, entry in row["files"].items():
            if not entry:
                continue
            if not unique[name] or entry["mtime"] != unique[name][-1]["mtime"]:
                unique[name].append(entry)
        entry = row["files"].get("client-status.json")
        if entry and isinstance(entry["value"].get("frame"), int):
            pair = (entry["mtime"], entry["value"]["frame"])
            if not statuses or pair != statuses[-1]:
                statuses.append(pair)
    elapsed = frames = 0
    for previous, current in zip(statuses, statuses[1:]):
        if current[0] > previous[0] and current[1] > previous[1]:
            elapsed += current[0] - previous[0]
            frames += current[1] - previous[1]
    clients = [e["value"] for e in unique["client-performance.json"]]
    render = [e["value"] for e in unique["render-performance.json"]]
    return {
        "camera_callback_hz": frames / elapsed if elapsed else None,
        "camera_callback_measurement_seconds": elapsed,
        "camera_callback_method": "client-status frame counter / file mtime; not a GPU FPS capture",
        "world_frame_mean_ms": distribution([e["world_frame"]["mean_ms"] for e in clients if e.get("world_frame", {}).get("samples", 0)]),
        "world_frame_p95_ms": distribution([e["world_frame"]["p95_ms"] for e in clients if e.get("world_frame", {}).get("samples", 0)]),
        "lua_callback_p95_ms": distribution([e["callback_interval"]["p95_ms"] for e in clients if e.get("callback_interval", {}).get("samples", 0)]),
        "lua_work_mean_ms": distribution([e["stages"]["total"]["mean_ms"] for e in clients if "total" in e.get("stages", {})]),
        "worker_interval_mean_ms": distribution([e.get("loop_interval_mean_ms") for e in render]),
        "worker_work_mean_ms": distribution([e.get("work_mean_ms") for e in render]),
        "input_to_camera_mean_ms": distribution([e.get("input_to_camera_mean_ms") for e in render if e.get("input_to_camera_samples", 0)]),
        "input_to_camera_max_ms": distribution([e.get("input_to_camera_max_ms") for e in render if e.get("input_to_camera_samples", 0)]),
        "latency_method": "native input snapshot timestamp to Lua camera commit; excludes display/GPU latency",
        "client_errors": [e["value"] for e in unique["client-status.json"] if e["value"].get("status") == "error"],
        "file_update_counts": {name: len(entries) for name, entries in unique.items()},
        "last_client_profile": clients[-1] if clients else None,
        "last_controls_profile": unique["controls-performance.json"][-1]["value"] if unique["controls-performance.json"] else None,
        "notes": ["Keep scene, resolution, foreground focus, camera pose, model counts and mode the same for comparisons.",
                  "An uncontrolled sample is observational only; do not attribute changes to v15.",
                  "World frame delta uses engine simulation time; pauses/time dilation invalidate conversion to render FPS."]
    }


def sample(args):
    rows = []
    started = time.monotonic()
    while time.monotonic() - started < args.seconds:
        row = {"elapsed": time.monotonic() - started, "unix": time.time(),
               "files": {name: read_json(args.bridge / name) for name in FILES}}
        try:
            raw = (args.bridge / "input-live.bin").read_bytes()
            v = INPUT.unpack(raw)
            row["input_live"] = {"sequence": v[1], "tick_ms": v[2], "unix": v[3],
                                 "flags": v[6], "forward": v[7], "strafe": v[8],
                                 "generation": v[9], "viewport_width": v[10], "viewport_height": v[11],
                                 "valid": v[0] == b"PALINP15" and v[1] == v[-1] and v[1] % 2 == 0}
        except (OSError, struct.error):
            row["input_live"] = None
        try:
            camera = CAMERA.unpack((args.bridge / "camera.bin").read_bytes())
            row["camera"] = {"position": camera[4:7], "feet": camera[7:10],
                             "rotation": camera[10:13], "vertical_fov": camera[13], "flags": camera[2]}
        except (OSError, struct.error):
            row["camera"] = None
        rows.append(row)
        time.sleep(args.interval)
    result = {"schema_version": 1, "label": args.label, "bridge": str(args.bridge),
              "started_utc": dt.datetime.fromtimestamp(rows[0]["unix"], dt.timezone.utc).isoformat() if rows else None,
              "duration_seconds": time.monotonic() - started, "summary": summarize(rows), "samples": rows}
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps({"output": str(args.out.resolve()), "label": args.label, "summary": result["summary"]}, ensure_ascii=False))


def compare(args):
    before, after = (json.loads(p.read_text()) for p in (args.before, args.after))
    metrics = {}
    for name in ("camera_callback_hz", "world_frame_mean_ms", "world_frame_p95_ms",
                 "lua_callback_p95_ms", "lua_work_mean_ms", "worker_interval_mean_ms",
                 "worker_work_mean_ms", "input_to_camera_mean_ms"):
        a, b = before["summary"].get(name), after["summary"].get(name)
        av = a["mean"] if isinstance(a, dict) else a
        bv = b["mean"] if isinstance(b, dict) else b
        metrics[name] = {"before": a, "after": b,
                         "change_percent": (bv / av - 1) * 100 if av and bv is not None else None}
    result = {"before": before["label"], "after": after["label"], "metrics": metrics,
              "controlled_comparison_confirmed": False,
              "notes": after["summary"]["notes"]}
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, ensure_ascii=False))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    collect = commands.add_parser("sample")
    collect.add_argument("--bridge", type=Path, default=DEFAULT_BRIDGE)
    collect.add_argument("--seconds", type=float, default=30)
    collect.add_argument("--interval", type=float, default=.05)
    collect.add_argument("--label", required=True)
    collect.add_argument("--out", type=Path, required=True)
    collect.set_defaults(function=sample)
    diff = commands.add_parser("compare")
    diff.add_argument("before", type=Path)
    diff.add_argument("after", type=Path)
    diff.add_argument("--out", type=Path)
    diff.set_defaults(function=compare)
    args = parser.parse_args()
    if args.command == "sample" and (args.seconds <= 0 or args.interval < .005):
        parser.error("seconds must be positive and interval at least 5ms")
    args.function(args)


if __name__ == "__main__":
    main()
