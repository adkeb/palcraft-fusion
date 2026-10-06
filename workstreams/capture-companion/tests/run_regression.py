"""Run only the new capture composition. Writes only inside this delta directory."""
import hashlib
import json
import subprocess
import time
from pathlib import Path


delta = Path(__file__).resolve().parents[1]
root = delta.parents[1]
lua = root.parent / 'palworld-live/research/lua-5.4.8/src/lua'
luac = lua.with_name('luac')
fixture = delta / 'tests/run'
for folder in ('entities', 'entity-capture-v1/textures'):
    (fixture / folder).mkdir(parents=True, exist_ok=True)
for path in fixture.rglob('*'):
    if path.is_file():
        path.unlink()

inputs = json.loads((delta / 'inputs.json').read_text())
for logical, item in inputs.items():
    assert hashlib.sha256((delta / 'base' / logical).read_bytes()).hexdigest() == item['sha256'], logical
sources = sorted((delta / 'proposals').rglob('*.lua')) + [delta / 'tests/capture_composition.lua']
for path in sources:
    subprocess.run([str(luac), '-p', str(path)], check=True, capture_output=True, text=True)
started = time.perf_counter()
result = subprocess.run([str(lua), str(delta / 'tests/capture_composition.lua'), str(root), str(delta), str(fixture)],
                        check=True, capture_output=True, text=True)
report = json.loads(result.stdout)
report['elapsed_seconds'] = round(time.perf_counter() - started, 6)
report['syntax_files_checked'] = len(sources)
report['regression_source_sha256'] = hashlib.sha256((delta / 'tests/capture_composition.lua').read_bytes()).hexdigest()
report['actual_module_sha256'] = {
    path: hashlib.sha256(Path(path).read_bytes()).hexdigest() for path in report.pop('actual_modules')
}
report['command'] = [str(lua), str(delta / 'tests/capture_composition.lua'), str(root), str(delta), str(fixture)]
(delta / 'verification.json').write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n')
print(json.dumps({key: value for key, value in report.items() if key not in ('actual_module_sha256', 'command')}, ensure_ascii=False))
