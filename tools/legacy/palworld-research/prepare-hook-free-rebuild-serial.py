# coding: utf-8
"""Prepare a local-only serial scheduling candidate from frozen v4 host; never deploy."""
import hashlib
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
source = ROOT / 'lab/hook-free-rebuild-v4.lua'
core = ROOT / 'lab/hook-free-rebuild-v4-core.lua'
assert hashlib.sha256(source.read_bytes()).hexdigest() == '8652cc5742877b9fa7f1926d9481019bba01f549d077d0fa70a27468a19dc332', 'frozen v4 host changed'
assert hashlib.sha256(core.read_bytes()).hexdigest() == '1152789b730b807110ac14b6a268cfe2a338ff6d9d20fcb64f75e8637d622ede', 'frozen v4 core changed'
s = source.read_text()
start = s.index('local ROOT=')
end = s.index('ExecuteInGameThread(function()runner.start();')
# Copy all persistent evidence, preflight, native call and observation logic verbatim.
header = """-- Lab-only serial host candidate. No automatic scheduling; load only inside a GT callback.
-- Frozen v4 core and all v4 arm/report/intent names are retained to preserve replay fences.
local source=debug.getinfo(1,'S').source
local canonical=source:gsub('\\\\','/'):lower()
assert(canonical=='@d:/palworldserver-lan/bridgelab/pal/binaries/win64/ue4ss/mods/pallivebridge/scripts/hook-free-rebuild-serial.lua','Exact BridgeLab serial host path required')
local directory=assert(source:match('^@(.*[/\\\\])'))
assert(type(IsInGameThread)=='function'and IsInGameThread(),'serial host must be loaded on game thread')
"""
tail = """-- Source scheduling metadata only: this is not proof of runtime isolation or safety.
runner.report.scheduling={variant='serial_gt_one_shot_candidate',rpc_main_loaded=false,
    async_pollers_registered=0,initial_delay_ms=5000,tick_delay_ms=1000,max_observation_seconds=30,
    max_tick_callbacks=30,core_sha256='1152789b730b807110ac14b6a268cfe2a338ff6d9d20fcb64f75e8637d622ede',
    frozen_host_sha256='8652cc5742877b9fa7f1926d9481019bba01f549d077d0fa70a27468a19dc332',
    runtime_isolation_verified=false}
return runner
"""
(ROOT / 'lab/hook-free-rebuild-serial.lua').write_text(header + s[start:end] + tail)
print('Prepared local serial host; frozen v4 source/core untouched.')
