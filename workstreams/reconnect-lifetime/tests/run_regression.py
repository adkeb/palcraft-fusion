"""Run the one directed reconnect lifecycle, writing only inside this delta."""
import hashlib
import json
import subprocess
import time
from pathlib import Path

delta = Path(__file__).resolve().parents[1]
root = delta.parents[1]
lua = root.parent / 'palworld-live/research/lua-5.4.8/src/lua'
fixture = delta / 'tests/run'
fixture.mkdir(parents=True, exist_ok=True)
(fixture / 'server-journal').mkdir(parents=True, exist_ok=True)
for path in fixture.rglob('*'):
    if path.is_file():
        path.unlink()
sources = sorted((delta / 'proposals').rglob('*.lua')) + [delta / 'tests/reconnect_lifetime.lua']
for path in sources:
    subprocess.run([str(lua.with_name('luac')), '-p', str(path)], check=True, text=True, capture_output=True)
started = time.perf_counter()
result = subprocess.run([str(lua), str(delta / 'tests/reconnect_lifetime.lua'), str(root), str(delta), str(fixture)],
                        check=True, text=True, capture_output=True)
report = json.loads(result.stdout)
report['elapsed_seconds'] = round(time.perf_counter() - started, 6)
report['syntax_files_checked'] = len(sources)
report['actual_source_sha256'] = {
    path: hashlib.sha256(Path(path).read_bytes()).hexdigest() for path in report.pop('actual_sources')
}
report['main_source_sha256'] = hashlib.sha256((delta / 'proposals/client/main.lua').read_bytes()).hexdigest()
report['regression_source_sha256'] = hashlib.sha256((delta / 'tests/reconnect_lifetime.lua').read_bytes()).hexdigest()
(delta / 'verification.json').write_text(json.dumps(report, indent=2) + '\n')
print(json.dumps({key: value for key, value in report.items() if key != 'actual_source_sha256'}))
