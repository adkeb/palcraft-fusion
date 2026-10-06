#!/usr/bin/env python3
"""Build this branch's Windows x64 DLL locally; never deploy or restart."""
import argparse
import hashlib
import json
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--zig", type=Path, default=root / "work/palworld-live/research/zig-aarch64-macos-0.15.2/zig")
parser.add_argument("--out", type=Path, default=Path(__file__).resolve().parent / "PalCraftRender-v15.dll")
args = parser.parse_args()
source = root / "work/minecraft-fusion/palcraft/render"
args.out.parent.mkdir(parents=True, exist_ok=True)
command = [str(args.zig), "c++", "-target", "x86_64-windows-gnu", "-std=c++17",
           "-O2", "-DNOMINMAX", "-Wall", "-Wextra", "-Wno-unknown-attributes",
           "-shared", "-I" + str(source / "sdk"),
           *(str(source / name) for name in ("palcraft.cpp", "controls.cpp", "ws.cpp", "compositor.cpp")),
           "-o", str(args.out), "-lws2_32", "-luser32", "-ld3d11", "-ldxgi"]
subprocess.run(command, check=True, cwd=root)
binary = args.out.read_bytes()
result = {"artifact": str(args.out.resolve()), "bytes": len(binary),
          "sha256": hashlib.sha256(binary).hexdigest(), "target": "x86_64-windows-gnu",
          "sources": {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
                      for p in (source / "palcraft.cpp", source / "controls.cpp", source / "controls.h", source / "input_transport.h")},
          "deployed": False}
args.out.with_suffix(".build.json").write_text(json.dumps(result, indent=2) + "\n")
print(json.dumps(result))
