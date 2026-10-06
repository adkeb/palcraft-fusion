#!/usr/bin/env python3
"""Repair only the unsupported link option; reuse the four compiled objects."""
import datetime
import hashlib
import json
import os
import struct
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parents[3]
work = Path(__file__).resolve().parent
paired = work / "frozen/capture-scope-v16-paired"
zig = root / "work/palworld-live/research/zig-aarch64-macos-0.15.2/zig"
artifact = paired / "PalCraftRender-v16.dll"
assert all((paired / "objects" / (n + ".obj")).is_file() for n in ("palcraft", "controls", "ws", "compositor"))
assert not artifact.exists(), "Do not replace an existing artifact."
os.nice(19)
command = [str(zig), "c++", "-target", "x86_64-windows-gnu", "-shared", "-fno-lto",
           *(str(paired / "objects" / (n + ".obj")) for n in ("palcraft", "controls", "ws", "compositor")),
           "-o", str(artifact), "-lws2_32", "-luser32", "-ld3d11", "-ldxgi"]
with (paired / "link.log").open("w") as log:
    subprocess.run(command, check=True, cwd=paired, stdout=log, stderr=log)
data = artifact.read_bytes()
pe = struct.unpack_from("<I", data, 0x3c)[0]
assert data[:2] == b"MZ" and data[pe:pe + 4] == b"PE\0\0"
machine, section_count = struct.unpack_from("<HH", data, pe + 4)
optional_bytes, characteristics = struct.unpack_from("<HH", data, pe + 20)
optional = pe + 24
assert machine == 0x8664 and struct.unpack_from("<H", data, optional)[0] == 0x20b and characteristics & 0x2000
sections = []
for i in range(section_count):
    offset = optional + optional_bytes + i * 40
    virtual_size, virtual_address, raw_size, raw_offset = struct.unpack_from("<IIII", data, offset + 8)
    sections.append((virtual_address, max(virtual_size, raw_size), raw_offset))
def rva(value):
    for start, length, offset in sections:
        if start <= value < start + length:
            return offset + value - start
    raise AssertionError("RVA outside section")
def string_at(value):
    start = rva(value)
    return data[start:data.index(b"\0", start)].decode("ascii")
exports_rva = struct.unpack_from("<I", data, optional + 112)[0]
exports_offset = rva(exports_rva)
count = struct.unpack_from("<I", data, exports_offset + 24)[0]
names_rva = struct.unpack_from("<I", data, exports_offset + 32)[0]
exports = [string_at(struct.unpack_from("<I", data, rva(names_rva) + 4 * i)[0]) for i in range(count)]
required = {"palcraft_commit_camera", "palcraft_suspend_actions", "palcraft_resume_actions"}
assert required <= set(exports), exports
imports_rva = struct.unpack_from("<I", data, optional + 120)[0]
imports = []
if imports_rva:
    cursor = rva(imports_rva)
    while any(data[cursor:cursor + 20]):
        name_rva = struct.unpack_from("<I", data, cursor + 12)[0]
        imports.append(string_at(name_rva)); cursor += 20
assert not any("libstdc++" in n.lower() or "libgcc" in n.lower() or "libwinpthread" in n.lower() for n in imports), imports
assert b"publish_frame" in data and b"source_generation" in data
source_pins = {p.relative_to(paired).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
               for p in paired.rglob("*") if p.is_file() and p.suffix in (".lua", ".cpp", ".h", ".hpp")}
base_manifest = json.loads((paired / "manifest.json").read_text())
result = {"built_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
          "base_bundle_id": base_manifest["bundle_id"], "frozen_dir": str(paired),
          "priority_nice": 19, "compiler_jobs_concurrent": 1, "source_recompiled_during_link_repair": False,
          "unsupported_linker_threads_override_removed": True, "linker_thread_count": "toolchain default;one link process",
          "artifact": str(artifact), "artifact_sha256": hashlib.sha256(data).hexdigest(), "artifact_bytes": len(data),
          "version_filename": artifact.name, "main_sha256": source_pins["client/main.lua"],
          "loader_change_only": "PalCraftRender-v15.dll -> PalCraftRender-v16.dll",
          "source_pins": source_pins, "link_command": command, "exports": exports, "imports": imports,
          "camera_protocol": "external96B v2;live112B prefix+u32LE@112+UTF8@116,max4096;flagsbit4",
          "stable_v15_not_overwritten": True, "deployed": False, "game_process_started": False,
          "base_runtime_status_version_field": 15}
(paired / "v16-build-manifest.json").write_text(json.dumps(result, indent=2) + "\n")
print(json.dumps({k: result[k] for k in ("artifact", "artifact_sha256", "artifact_bytes", "main_sha256", "exports", "imports")}))
