#!/usr/bin/env python3
"""Run the bounded offline integration fixture with the already bundled Lua executable."""
import json
import hashlib
import subprocess
import tempfile
import time
from pathlib import Path

PALCRAFT = Path(__file__).resolve().parents[2]
BASE = PALCRAFT.parents[2]
LUA = BASE / 'work/palworld-live/research/lua-5.4.8/src/lua'
LUAC = LUA.with_name('luac')
CODEC = BASE / 'work/palworld-live/bridge/PalLiveBridge/Scripts/json.lua'
EVIDENCE = PALCRAFT / 'runtime/evidence'


def main():
    EVIDENCE.mkdir(parents=True, exist_ok=True)
    started = time.monotonic()
    modules = list((PALCRAFT / 'runtime').glob('*.lua')) + [PALCRAFT / p for p in ('client/features.lua', 'server/features.lua')]
    for path in modules:
        subprocess.run([str(LUAC), '-p', str(path)], check=True, capture_output=True, text=True)
    with tempfile.TemporaryDirectory(prefix='palcraft-runtime-') as directory:
        fixture = Path(directory)
        (fixture / 'auth').mkdir()
        (fixture / 'entities').mkdir()
        pins = PALCRAFT / 'runtime/pins/entity_combat_candidate_v1/server'
        command = [str(LUA), str(PALCRAFT / 'runtime/tests/runtime_test.lua'), str(PALCRAFT), str(CODEC), str(fixture), str(EVIDENCE / 'offline-tests.json'), str(pins if pins.exists() else PALCRAFT / 'server')]
        result = subprocess.run(command, capture_output=True, text=True, timeout=20)
        (EVIDENCE / 'offline-tests.log').write_text(result.stdout + result.stderr)
        if result.returncode:
            print(result.stdout + result.stderr)
            raise SystemExit(result.returncode)
    evidence = json.loads((EVIDENCE / 'offline-tests.json').read_text())
    evidence.update(elapsed_s=round(time.monotonic() - started, 4), operating_mode='night_low_power', processes='one Lua fixture, no game processes')
    overrides_file = PALCRAFT / 'runtime/pins/overrides.json'
    overrides = json.loads(overrides_file.read_text()) if overrides_file.exists() else {}
    evidence['source_sha256'] = {name: hashlib.sha256(Path(overrides.get(name, str(PALCRAFT / name))).read_bytes()).hexdigest() for name in evidence['real_modules']}
    (EVIDENCE / 'offline-tests.json').write_text(json.dumps(evidence, indent=2) + '\n')
    print(json.dumps(evidence))


if __name__ == '__main__':
    main()
