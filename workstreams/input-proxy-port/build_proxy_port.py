#!/usr/bin/env python3
"""Compile only the changed WS-start caller and reuse the three exact ddef objects."""
import datetime
import hashlib
import json
import os
import shutil
import subprocess
from pathlib import Path
from pe_reader import pe_report

WORK = Path(__file__).resolve().parent
ROOT = WORK.parents[3]
SOURCE = WORK / "proposal"
INPUTS = json.loads((WORK / "inputs.json").read_text())
BASE = Path(INPUTS["base_directory"])
ARTIFACT = WORK / INPUTS["new_artifact_filename"]
ZIG = ROOT / "work/palworld-live/research/zig-aarch64-macos-0.15.2/zig"


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


assert not ARTIFACT.exists(), "Never overwrite an existing immutable artifact."
assert sha(BASE / "PalCraftRender-v16-portable-operator.dll") == INPUTS["base_DLL_sha256"]
assert sha(BASE / "build-manifest.json") == INPUTS["base_manifest_sha256"]
for name, pin in INPUTS["source_pins"].items():
    assert sha(SOURCE / name) == pin, name
    if name != INPUTS["only_changed_source"]:
        assert pin == INPUTS["base_source_pins"][name], name
objects = WORK / "objects"
logs = WORK / "logs"
objects.mkdir(exist_ok=True); logs.mkdir(exist_ok=True)
reused = {}
for name in ("controls", "ws", "compositor"):
    original = Path(INPUTS["base_object_directory"]) / (name + ".obj")
    copied = objects / original.name
    expected = INPUTS["base_object_pins"][original.name]
    assert sha(original) == expected and not copied.exists()
    shutil.copy2(original, copied)
    assert sha(copied) == expected
    reused[name] = {"source": str(original), "sha256": expected}
os.nice(19)
compile_command = [str(ZIG), "c++", "-target", "x86_64-windows-gnu", "-std=c++17", "-O2", "-DNOMINMAX",
                   "-Wall", "-Wextra", "-Wno-unknown-attributes", "-fno-lto", "-I" + str(SOURCE / "render/sdk"),
                   "-c", str(SOURCE / "render/palcraft.cpp"), "-o", str(objects / "palcraft.obj")]
print("compile palcraft only (nice19, sequential)", flush=True)
with (logs / "palcraft.log").open("w") as log:
    subprocess.run(compile_command, cwd=SOURCE, check=True, stdout=log, stderr=log)
link_command = [str(ZIG), "c++", "-target", "x86_64-windows-gnu", "-shared", "-fno-lto",
                *(str(objects / (name + ".obj")) for name in ("palcraft", "controls", "ws", "compositor")),
                "-o", str(ARTIFACT), "-lws2_32", "-luser32", "-ld3d11", "-ldxgi"]
print("link independent proxy-port candidate", flush=True)
with (logs / "link.log").open("w") as log:
    subprocess.run(link_command, cwd=SOURCE, check=True, stdout=log, stderr=log)
pe = pe_report(ARTIFACT)
base_pe = pe_report(BASE / "PalCraftRender-v16-portable-operator.dll")
assert pe["exports"] == base_pe["exports"] and pe["imports"] == base_pe["imports"]
data = ARTIFACT.read_bytes()
assert "PALCRAFT_HOST_PROXY_PORT".encode("utf-16-le") in data
assert "PALCRAFT_NATIVE_WS_PORT".encode("utf-16-le") not in data
for marker in (b"PALINP15", b"publish_frame", b"source_generation"):
    assert marker in data
assert sha(BASE / "PalCraftRender-v16-portable-operator.dll") == INPUTS["base_DLL_sha256"]
base_manifest = json.loads((BASE / "build-manifest.json").read_text())
result = {
    "schema": "palcraft-host-proxy-port-build-v1", "status": "compiled_independent_candidate",
    "built_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "artifact": str(ARTIFACT), "artifact_sha256": sha(ARTIFACT), "artifact_bytes": len(data),
    "source_artifact_basename": ARTIFACT.name, "installed_basename": INPUTS["installed_basename"],
    "target": "PalCraft-Client/Pal/Binaries/Win64/" + INPUTS["installed_basename"],
    "role": "existing client native render/camera/input/operator; selected owned loopback auth proxy",
    "exact_base": {"directory": str(BASE), "DLL_sha256": INPUTS["base_DLL_sha256"], "manifest_sha256": INPUTS["base_manifest_sha256"]},
    "only_changed_source": INPUTS["only_changed_source"], "source_pins": INPUTS["source_pins"],
    "source_reversal_exact": True, "main_unchanged_sha256": INPUTS["main_unchanged_sha256"],
    "main_loader_unchanged": base_manifest["main_loader"],
    "proxy_port_contract": {"environment": "PALCRAFT_HOST_PROXY_PORT", "type": "strict ASCII decimal", "range": [1, 65535],
                            "absent_legacy_default": 25599, "invalid_explicit": "refuse before WsClient construction/start; no fallback", "loopback": "127.0.0.1",
                            "read_once": "existing worker startup, before WS initialization", "B_profile_requirement": "launcher/profile supplies a unique owned authentication-proxy port explicitly"},
    "authentication_and_WS_code": "unchanged same WsClient and original authentication route; no second socket/loop",
    "controls_input_form_capture_rawMC_HOST_ACK": "all unchanged ddef bytes except WS startup selection",
    "external_UTF8_pair": base_manifest["external_UTF8_pair"],
    "priority_nice": 19, "compiler_jobs_concurrent": 1, "changed_translation_units_compiled": 1,
    "linker_thread_count": "toolchain default; one link process", "commands": [compile_command, link_command],
    "reused_objects": reused, "object_pins": {f.name: sha(f) for f in objects.glob("*.obj")},
    "pe": pe, "compile_link_logs": {f.name: f.stat().st_size for f in logs.glob("*.log")},
    "verification": {"path": str(WORK / "verification.json"), "sha256": sha(WORK / "verification.json"), "new_cases": 23,
                     "boundary": "actual source parser/startup with mocked Win32 env; no real game or proxy connection"},
    "old_matrices_repeated": False, "immutable_ddef_918_8c_modified": False, "current10_1_modified": False,
    "head_modified": False, "deployed": False, "game_RPC_or_start_calls": 0,
    "actual_B_endpoint_M01_portable_form_F5_acceptance": "pending separate runtime owner windows",
}
assert not any(result["compile_link_logs"].values())
(WORK / "build-manifest.json").write_text(json.dumps(result, indent=2) + "\n")
print(json.dumps({k: result[k] for k in ("artifact", "artifact_sha256", "artifact_bytes", "installed_basename", "main_unchanged_sha256")}))
