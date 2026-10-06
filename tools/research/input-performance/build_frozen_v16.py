#!/usr/bin/env python3
"""One low-priority sequential build of the pinned scoped-camera producer."""
import datetime
import hashlib
import json
import os
import shutil
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parents[3]
work = Path(__file__).resolve().parent
original = work / "frozen/capture-scope-next-abddbfe4b276"
original_manifest = json.loads((original / "manifest.json").read_text())
for name, expected in original_manifest["files"].items():
    assert hashlib.sha256((original / name).read_bytes()).hexdigest() == expected, name
paired = work / "frozen/capture-scope-v16-paired"
assert not paired.exists(), "Build directory already exists; do not silently replace an artifact."
shutil.copytree(original, paired)
render = paired / "render"
head_render = root / "work/minecraft-fusion/palcraft/render"
for name in ("ws.cpp", "ws.h", "compositor.cpp", "compositor.h"):
    shutil.copy2(head_render / name, render / name)
shutil.copytree(head_render / "sdk", render / "sdk")
main = paired / "client/main.lua"
main_text = main.read_text()
assert main_text.count("PalCraftRender-v15.dll") == 1
main.write_text(main_text.replace("PalCraftRender-v15.dll", "PalCraftRender-v16.dll"))
zig = root / "work/palworld-live/research/zig-aarch64-macos-0.15.2/zig"
objects = paired / "objects"
objects.mkdir()
artifact = paired / "PalCraftRender-v16.dll"
flags = ["-target", "x86_64-windows-gnu", "-std=c++17", "-O2", "-DNOMINMAX",
         "-Wall", "-Wextra", "-Wno-unknown-attributes", "-fno-lto", "-I" + str(render / "sdk")]
os.nice(19)
commands = []
with (paired / "compile.log").open("w") as log:
    for name in ("palcraft", "controls", "ws", "compositor"):
        command = [str(zig), "c++", *flags, "-c", str(render / (name + ".cpp")),
                   "-o", str(objects / (name + ".obj"))]
        commands.append(command)
        subprocess.run(command, check=True, cwd=paired, stdout=log, stderr=log)
    command = [str(zig), "c++", "-target", "x86_64-windows-gnu", "-shared", "-fno-lto",
               *(str(objects / (n + ".obj")) for n in ("palcraft", "controls", "ws", "compositor")),
               "-o", str(artifact), "-Wl,--threads=1", "-lws2_32", "-luser32", "-ld3d11", "-ldxgi"]
    commands.append(command)
    subprocess.run(command, check=True, cwd=paired, stdout=log, stderr=log)
all_files = {p.relative_to(paired).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
             for p in paired.rglob("*") if p.is_file() and p.suffix in (".lua", ".cpp", ".h", ".hpp")}
result = {
    "built_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "base_bundle_id": original_manifest["bundle_id"], "frozen_dir": str(paired),
    "priority_nice": 19, "compiler_jobs_concurrent": 1, "linker_threads": 1,
    "artifact": str(artifact), "artifact_sha256": hashlib.sha256(artifact.read_bytes()).hexdigest(),
    "artifact_bytes": artifact.stat().st_size, "version_filename": artifact.name,
    "main_sha256": hashlib.sha256(main.read_bytes()).hexdigest(),
    "loader_change_only": "PalCraftRender-v15.dll -> PalCraftRender-v16.dll",
    "source_pins": all_files, "commands": commands,
    "camera_protocol": "96B v2 external;112B live header+u32LE at112+UTF8 scope JSON at116,max4096;flagbit4",
    "stable_v15_not_overwritten": True, "deployed": False, "game_process_started": False,
    "base_runtime_status_version_field": 15
}
(paired / "v16-build-manifest.json").write_text(json.dumps(result, indent=2) + "\n")
print(json.dumps({k: result[k] for k in ("artifact", "artifact_sha256", "artifact_bytes", "main_sha256", "priority_nice", "compiler_jobs_concurrent")}))
