#!/usr/bin/env python3
"""Serial, low-priority offline correctness checks; no runtime calls or benchmarks."""
import datetime
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

TASK = Path(__file__).resolve().parent
BASE = TASK.parents[2]
PAL = BASE / 'work/minecraft-fusion/palcraft'
LUA = BASE / 'work/palworld-live/research/lua-5.4.8/src/lua'
PYTHON = BASE / 'work/minecraft-fusion/exchange-test-runtime/venv/bin/python'
CODEC = BASE / 'work/palworld-live/bridge/PalLiveBridge/Scripts/json.lua'


def run(name, command):
    proc = subprocess.run([str(x) for x in command], cwd=BASE, capture_output=True, text=True)
    result = {'name': name, 'exit_code': proc.returncode, 'passed': proc.returncode == 0,
              'command': [str(x) for x in command], 'stdout': proc.stdout, 'stderr': proc.stderr}
    if proc.returncode:
        raise RuntimeError(json.dumps(result, ensure_ascii=False))
    return result


def main():
    if hasattr(os, 'nice'):
        os.nice(19)
    checks = []
    checks.append(run('lua_syntax', [LUA.with_name('luac'), '-p', PAL / 'server/exchange_escrow.lua']))
    checks.append(run('probe_syntax', [LUA.with_name('luac'), '-p', TASK / 'escrow_lab_probe.lua']))
    native = TASK / 'test_credit'
    dependencies = list(TASK.glob('*.hpp')) + [TASK / 'test_credit.cpp', TASK / 'escrow_credit.cpp']
    if not native.exists() or any(p.stat().st_mtime_ns > native.stat().st_mtime_ns for p in dependencies):
        checks.append(run('one_worker_native_mock_compile', ['/usr/bin/clang++', '-std=c++17', '-O0', TASK / 'test_credit.cpp', '-o', native]))
    lua = run('lua_adapter_filter_faults', [LUA, TASK / 'test_escrow.lua', PAL / 'server/exchange_escrow.lua', CODEC])
    lua['cases'] = json.loads(lua['stdout'].split('RESULT ')[-1])['passed']
    checks.append(lua)
    py = run('python_receipt_witness_tests', [PYTHON, TASK / 'test_escrow.py', '-v'])
    py['cases'] = int(re.search(r'Ran (\d+) tests', py['stderr'])[1])
    checks.append(py)
    cpp = run('native_candidate_mock_gates', [native])
    cpp['cases'] = int(re.search(r'native_credit_cases=(\d+)', cpp['stdout'])[1])
    checks.append(cpp)
    source_files = [PAL / 'server/exchange_escrow.lua', PAL / 'mcp/escrow_credit.py', PAL / 'mcp/escrow_witness.py', PAL / 'mcp/escrow_rehydrate.py', PAL / 'mcp/escrow_io.py'] + sorted(TASK.glob('*.cpp')) + sorted(TASK.glob('*.hpp')) + [TASK / 'escrow_lab_probe.lua']
    save = BASE / 'work/palworld-live/lab/serial-chest-after-Level.sav'
    evidence = {'status': 'offline_checks_passed_runtime_validation_pending',
                'updated_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
                'power_mode': 'night_low_power', 'checks_serial': True, 'process_priority': 'nice19',
                'runtime_verified': False, 'no_rpc_or_service_or_client_actions': True,
                'checks': checks, 'source_sha256': {str(p.relative_to(BASE)): hashlib.sha256(p.read_bytes()).hexdigest() for p in source_files},
                'historical_actual_save': {'path': str(save.relative_to(BASE)), 'sha256': hashlib.sha256(save.read_bytes()).hexdigest(),
                                          'containers': 1404, 'ordinary_chests': 19, 'outside_base_chests': 0,
                                          'isolation_verified': False},
                'windows_build_evidence': 'work/minecraft-fusion/escrow-storage/windows-build-evidence.json',
                'remaining': ['v3 owner wiring', 'isolated_windows_loader_smoke', 'normal_player_open_transport_base_supply_challenges',
                              'actual_one_item_mc_debit_to_escrow_produce_trial', 'guard_restore_before_reconnect_and_late_witness_trial',
                              'actual_new_process_full_world_rehydration_certificate_for_rearm']}
    path = TASK / 'offline-evidence.json'
    path.write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps({'passed': True, 'lua_cases': lua['cases'], 'python_tests': py['cases'], 'native_cases': cpp['cases'],
                      'power_mode': evidence['power_mode'], 'runtime_verified': False, 'evidence': str(path)}, ensure_ascii=False))


if __name__ == '__main__':
    main()
